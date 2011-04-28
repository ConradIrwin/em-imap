module EventMachine
  module Imap
    CRLF = "\r\n"
    module Connection
      include ListeningDeferrable
      include Imap::CommandSender
      include Imap::ResponseParser

      def self.connect(host, port, ssl=false)
        EventMachine.connect(host, port, self).tap do |conn|
          conn.start_tls if ssl
        end
      end

      def post_init
        @untagged_responses = {}
        @tagged_listeners = {}
        @listeners = []
        super
        errback do |e|
          @listeners.each{ |listener| listener.fail e }
        end
        listen_for_bye
      end

      def untagged_responses
        @untagged_responses
      end

      def send_command(cmd, *args, &block)
        Command.new(next_tag!, cmd, args, &block).tap do |command|
          add_to_listener_pool(command)
          listen_for_tagged_response(command)
          send_command_object(command)
        end
      end

      def add_to_listener_pool(listener)
        @listeners << listener.bothback{ @listeners.delete listener }
      end

      def receive_response(response)
        @listeners.each{ |listener| listener.receive_event response }
      end

      def listen_for_tagged_response(command)
        command.listen do |response|
          if response.is_a?(Net::IMAP::TaggedResponse) && response.tag == command.tag
            case response.name
            when "NO"
              command.fail Net::IMAP::NoResponseError.new(response.data.text)
            when "BAD"
              command.fail Net::IMAP::BadResponseError.new(response.data.text)
            else
              command.succeed response
            end
          end
        end
      end

      def listen_for_bye
        add_response_handler do |response|
          if response.is_a?(Net::IMAP::UntaggedResponse) && response.name == "BYE"
            if stopped?
              succeed
            else
              fail Net::IMAP::ByeResponseError.new(response.raw_data)
            end
          end
        end
      end

      def add_response_handler(&block)
        Listener.new(&block).tap do |listener|
          listener.stopback{ listener.succeed }
          add_to_listener_pool(listener)
        end
      end

      def unbind
        if stopped?
          succeed
        else
          fail EOFError.new("end of file reached")
        end
      end

      # Provides a next_tag! method to generate unique tags
      # for an Imap session.
      module TagSequence
        def post_init
          super
          # Copying Net::IMAP
          @tag_prefix = "RUBY"
          @tagno = 0
        end

        def next_tag!
          @tagno += 1
          "%s%04d" % [@tag_prefix, @tagno]
        end
      end

      # Intercepts send_data and receive_data and logs them to STDOUT,
      # this should be the last module included.
      module Debug
        def send_data(data)
          puts "C: #{data.inspect}"
          super
        end

        def receive_data(data)
          puts "S: #{data.inspect}"
          super
        end
      end
      include Imap::Connection::TagSequence
      include Imap::Connection::Debug
    end
  end
end

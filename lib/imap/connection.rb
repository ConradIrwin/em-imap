require 'net/imap'
require File.dirname( __FILE__ ) + '/response_parser.rb'
require File.dirname( __FILE__ ) + '/command_sender.rb'
module EventMachine
  module Imap
    CRLF = "\r\n"
    module Connection
      attr_reader :waiting

      def self.connect(host, port, ssl=false)
        EventMachine.connect(host, port, self).tap do |conn|
          conn.start_tls if ssl
        end
      end

      def post_init
        super
        @tagged_commands = {}
        @named_responses = {}
      end

      def send_command(cmd, *args)
        Command.new(next_tag!, cmd, args).tap do |command|

          add_to_listener_pool(command)
          command.bothback do
            remove_from_listener_pool(command)
          end

          send_command_object(command)
        end
      rescue => e
        fail_all e
      end

      # See also Net::IMAP#receive_responses
      def receive_response(response)
        case response
        when Net::IMAP::TaggedResponse

          if @tagged_commands[response.tag]
            complete_response @tagged_commands[response.tag], response
          else
            # The server has responded to a request we didn't make, let's bail.
            fail_all Net::IMAP::ResponseParseError.new(response.raw_data)
          end

        when Net::IMAP::UntaggedResponse
          if response.name == "BYE"
            fail_all Net::IMAP::ByeResponseError.new(response.raw_data)
          else
            record_response(response.name, response.data)
          end

        when Net::IMAP::ContinuationRequest
          receive_continuation response

        end
      rescue => e
        fail_all e
      end

      # Net::IMAP#pick_up_tagged_response
      def complete_response(command, response)
        case response.name
        when "NO"
          command.fail Net::IMAP::NoResponseError.new(response.data.text)
        when "BAD"
          command.fail Net::IMAP::BadResponseError.new(response.data.text)
        else
          command.succeed response, @named_responses.delete(command.cmd)
        end
      end

      # NOTE: This is a pretty horrible way to do things.
      def record_response(name, response)
        @named_responses[name] ||= []
        @named_responses[name] << response
      end

      def add_to_listener_pool(command)
        @tagged_commands[command.tag] = command
      end

      def remove_from_listener_pool(command)
        @tagged_commands.delete command.tag
      end

      def fail_all(error)
        @tagged_commands.values.each do |command|
          command.fail error
        end
        raise error
      end

      def unbind
        unless @tagged_commands.empty?
          fail_all EOFError.new("end of file reached")
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

      include Imap::CommandSender
      include Imap::ResponseParser
      include Imap::Connection::TagSequence
      include Imap::Connection::Debug
    end
  end
end

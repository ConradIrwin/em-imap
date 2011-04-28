module EventMachine
  module Imap
    # Provides a send_command_object method that serializes command objects
    # and uses send_data on them. This is the ugly sister to ResponseParser.
    module CommandSender
      # Ugly hack to get at the Net::IMAP string formatting routines.
      # (FIXME: Extract into its own module and rewrite)
      class FakeNetImap < Net::IMAP
        def initialize(command, imap_connection)
          @command = command
          @connection = imap_connection
        end

        def put_string(str)
          @connection.send_string str, @command
        end

        def send_literal(str)
          @connection.send_literal str, @command
        end

        public :send_data
      end

      # This is a method that synchronously converts the command into fragments
      # of string.
      #
      # If you pass something that cannot be serialized, an exception will be raised.
      # If however, something fails at the socket level, the command will be failed.
      def send_command_object(command)
        sender = FakeNetImap.new(command, self)

        sender.put_string "#{command.tag} #{command.cmd}"
        command.args.each do |arg|
          sender.put_string " "
          sender.send_data arg
        end
        sender.put_string CRLF
      end

      # See Net::IMAP#authenticate
      def send_authentication_data(auth_handler, command)
        when_not_awaiting_continuation do
          waiter = await_continuations do |response|
            begin
              data = auth_handler.process(response.data.text.unpack("m")[0])
              s = [data].pack("m").gsub(/\n/, "")
              send_data(s + CRLF)
            rescue => e
              command.fail e
            end
          end
          command.bothback{ |*args| waiter.stop }
        end
      end

      def send_string(str, command)
        when_not_awaiting_continuation do
          begin
            send_line_buffered str
          rescue => e
            command.fail e
          end
        end
      end

      def send_literal(literal, command)
        when_not_awaiting_continuation do
          begin
            send_line_buffered "{" + literal.size.to_s + "}" + CRLF
          rescue => e
            command.fail e
          end
          waiter = await_continuations do
            begin
              send_data literal
            rescue => e
              command.fail e
            end
            waiter.stop
          end
          command.errback{ waiter.stop }
        end
      end

      module LineBuffer
        def post_init
          super
          @line_buffer = ""
        end

        def send_line_buffered(str)
          @line_buffer += str
          while eol = @line_buffer.index(CRLF)
            to_send = @line_buffer.slice! 0, eol + CRLF.size
            send_data to_send
          end
        end
      end
      include Imap::CommandSender::LineBuffer
      include Imap::ContinuationSynchronisation
    end
  end
end

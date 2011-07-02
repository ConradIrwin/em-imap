module EventMachine
  module IMAP
    # Provides a send_command_object method that serializes command objects
    # and uses send_data on them. This is the ugly sister to ResponseParser.
    module CommandSender
      # This is a method that synchronously converts the command into fragments
      # of string.
      #
      # If you pass something that cannot be serialized, an exception will be raised.
      # If however, something fails at the socket level, the command will be failed.
      def send_command_object(command)
        Formatter.format(command) do |to_send|
          if to_send.is_a? Formatter::Literal
            send_literal to_send.str, command
          else
            send_string  to_send, command
          end
        end
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

      def prepare_idle_continuation(command)
        when_not_awaiting_continuation do
          waiter = await_continuations
          command.stopback do
            waiter.stop
            begin
              send_data "DONE\r\n"
            rescue => e
              command.fail e
            end
          end
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
      include IMAP::CommandSender::LineBuffer
      include IMAP::ContinuationSynchronisation
    end
  end
end

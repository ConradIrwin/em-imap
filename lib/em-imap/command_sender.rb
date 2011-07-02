module EventMachine
  module IMAP
    # Used to send commands, and various other pieces of data, to the IMAP
    # server as they are needed. Plugs in the ContinuationSynchronisation module
    # so that the outgoing channel is free of racey-behaviour.
    module CommandSender
      # Send a command to the IMAP server.
      #
      # @param command, The command to send.
      #
      # This method has two phases, the first of which is to convert your
      # command into tokens for sending over the network, and the second is to
      # actually send those fragments.
      #
      # If the conversion fails, a Net::IMAP::DataFormatError will be raised
      # which you should handle synchronously. If the sending fails, then the
      # command will be failed asynchronously.
      #
      def send_command_object(command)
        Formatter.format(command) do |to_send|
          if to_send.is_a? Formatter::Literal
            send_literal to_send.str, command
          else
            send_string  to_send, command
          end
        end
      end

      # Send some normal (binary/string) data to the server.
      #
      # @param str, the data to send
      # @param command, the command for which the data is being sent.
      #
      # This uses the LineBuffer, and fails the command if the network
      # connection has died for some reason.
      #
      def send_string(str, command)
        when_not_awaiting_continuation do
          begin
            send_line_buffered str
          rescue => e
            command.fail e
          end
        end
      end

      # Send an IMAP literal to the server.
      #
      # @param literal, the string to send.
      # @param command, the command associated with this string.
      #
      # Sending literals is a somewhat complicated process:
      #
      # Step 1. Client tells the server how big the literal will be.
      #   (and at the same time shows the server the contents of the command so
      #   far)
      # Step 2. The server either accepts (with a ContinuationResponse) or
      #   rejects (with a BadResponse) the continuation based on the size of the
      #   literal, and the validity of the line so far.
      # Step 3. The client sends the literal, followed by a linefeed, and then
      # continues with sending the rest of the command.
      #
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

      # Pass a challenge/response between the server and the auth_handler.
      #
      # @param auth_handler, an authorization handler.
      # @param command, the associated AUTHORIZE command.
      #
      # This can be called several times in one authorization handshake
      # depending on how many messages the server wishes to see from the
      # auth_handler.
      #
      # If the auth_handler raises an exception, or the network connection dies
      # for some reason, the command will be failed.
      #
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

      # Register a stopback on the IDLE command that sends the DONE
      # continuation that the server is waiting for.
      #
      # @param command, The IDLE command.
      #
      # This blocks the outgoing connection until the IDLE command is stopped,
      # as required by RFC 2177.
      #
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


      # Buffers out-going string sending by-line.
      #
      # This is safe to do for IMAP because the client always ends transmission
      # on a CRLF (for awaiting continuation requests, and for ending commands)
      #
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

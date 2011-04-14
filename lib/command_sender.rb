module EventMachine
  module ImapConnection
    # Provides a send_command_object method that serializes command objects
    # and uses send_data on them. This is the ugly sister to ResponseParser.
    module CommandSender
      # Ugly hack to get at the Net::IMAP string formatting routines.
      # (FIXME: Extract into its own module and rewrite)
      class FakeNetImap < Net::IMAP
        def initialize(command, imap_connection)
          @command = command
          @connection = imap_connection

          @send_buffer = ""
        end

        # Line-buffered sending ftw. (Sends all the complete lines that are available)
        def put_string(str)
          @send_buffer += str

          eol = @send_buffer.rindex(CRLF)
          if eol
            to_send = @send_buffer.slice! 0, eol + CRLF.size
            @connection.send_data to_send
          end
        rescue => e
          @command.fail e
        end

        # This is a translation of Net::Imap#send_literal.
        # Before the client sends a literal to the server, we have to wait for its permission
        # (using a ContinuationRequestListener)
        def send_literal(str)
          raise "Sending a string containing a newline doesn't work yet, syntactic rewriting must happen"
          put_string("{" + str.size.to_s + "}" + CRLF)
          @connection.add_listener(ContinuationRequestListener.new(@connection)).callback do
            put_string(str)
          end.errback do |exception|
            @command.fail exception
          end
        end

        public :send_data
      end

      def send_command_object(command)
        sender = FakeNetImap.new(command, self)

        sender.put_string "#{command.tag} #{command.cmd}"
        command.args.each do |arg|
          sender.put_string " "
          sender.send_data arg
        end
        sender.put_string CRLF
      rescue => e
        command.fail e
      end
    end
  end
end

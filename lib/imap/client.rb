module EventMachine
  module Imap
    class Client
      def initialize(connection)
        @connection = connection
      end

      def disconnect
        @connection.close_connection
      end

      ## 6.1 Client commands - any state.

      def capability
        one_data_response("CAPABILITY")
      end

      def noop
        tagged_response("NOOP")
      end

      # Logout and close the connection.
      def logout
        tagged_response("LOGOUT").errback do |e|
          if e.is_a? Net::IMAP::ByeResponseError
            # RFC 3501 says the server MUST send a BYE response and then close the connection.
            disconnect
            succeed
          end
        end.callback do |response|
          fail Net::IMAP::ResponseParseError.new("Received the wrong response to LOGOUT: #{response}")
        end
      end

      ## 6.2 Client commands - "Not authenticated" state

      def starttls
        raise NotImplementedError
      end

      def authenticate(auth_type, *args)
        auth_type = auth_type.upcase
        raise "bleargh"
      end


      def create(mailbox)
        tagged_response("CREATE")
      end

      def delete(mailbox)
        tagged_response("DELETE")
      end

      def examine(mailbox)
        tagged_response("EXAMINE")
      end

      def login(username, password)
        tagged_response("LOGIN", username, password)
      end

      def logout
        tagged_response("LOGOUT")
      end

      def select(mailbox)
        tagged_response("SELECT", mailbox)
      end

      def subscribe(mailbox)
        send_command("SUBSCRIBE", mailbox)
      end

      def rename(mailbox, newname)
        tagged_response("RENAME", mailbox, newname)
      end

      private
      
      # The callback of a Command returns both a tagged response,
      # and optionally a list of untagged responses that were
      # generated at the same time.
      def tagged_response(*command)
        send_command(*command).transform{ |response, data| response }
      end

      def one_data_response(*command)
        send_command(*command).transform{ |response, data| data.last }
      end

      def multi_data_response(*command)
        send_command(*command).transform{ |response, data| data }
      end

      def send_command(cmd, *args)
        @connection.send_command(cmd, *args)
      end
    end
  end
end

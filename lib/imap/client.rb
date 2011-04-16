module EventMachine
  module Imap
    class Client
      include Imap::Authenticators

      def initialize(connection)
        @connection = connection
      end

      def disconnect
        @connection.close_connection
      end

      ## 6.1 Client Commands - Any State.

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

      ## 6.2 Client Commands - Not Authenticated State

      def starttls
        raise NotImplementedError
      end

      def authenticate(auth_type, *args)
        auth_type = auth_type.upcase
        auth_handler = authenticator(auth_type, *args)

        tagged_response('AUTHENTICATE', auth_type).tap do |command|
          @connection.send_authentication_data(auth_handler, command)
        end
      end

      def login(username, password)
        tagged_response("LOGIN", username, password)
      end

      ## 6.3 Client Commands - Authenticated State

      # TODO: Figure out API for EXISTS, RECENT, etc.
      def select(mailbox)
        tagged_response("SELECT", mailbox)
      end

      def examine(mailbox)
        tagged_response("EXAMINE", mailbox)
      end

      def create(mailbox)
        tagged_response("CREATE", mailbox)
      end

      def delete(mailbox)
        tagged_response("DELETE", mailbox)
      end

      def rename(mailbox, newname)
        tagged_response("RENAME", mailbox, newname)
      end

      def subscribe(mailbox)
        tagged_response("SUBSCRIBE", mailbox)
      end

      def unsubscribe(mailbox)
        tagged_response("UNSUBSCRIBE", mailbox)
      end

      def list(refname, mailbox)
        multi_data_response("LIST", refname, mailbox)
      end

      def lsub(refname, mailbox)
        multi_data_response("LSUB", rename, mailbox)
      end

      def status(mailbox, attr)
        # FIXME: Why is this transform needed?
        one_data_response("STATUS", mailbox, attr).transform do |response|
          response.attr
        end
      end

      def append(mailbox, message, flags=nil, date_time=nil)
        args = [mailbox]
        args << flags if flags
        args << date_time if date_time
        args << Net::IMAP::Literal.new(message)
        tagged_response("APPEND" *args)
      end

      # 6.4 Client Commands - Selected State
      
      def check
        tagged_response("CHECK")
      end

      def close
        tagged_response("CLOSE")
      end
      
      def expunge
        tagged_response("EXPUNGE")
      end

      def search(keys, charset)

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

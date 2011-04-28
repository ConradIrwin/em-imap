module EventMachine
  module Imap
    # TODO: Anything that accepts or returns a mailbox name should have UTF7 support.
    class Client
      include Imap::Authenticators

      def initialize(connection)
        @connection = connection
      end

      def disconnect
        @connection.close_connection
      end

      def untagged_responses
        @connection.untagged_responses
      end
      alias :responses :untagged_responses

      ## 6.1 Client Commands - Any State.

      def capability
        one_data_response("CAPABILITY")
      end

      def noop
        tagged_response("NOOP")
      end

      # Logout and close the connection.
      def logout
        command = tagged_response("LOGOUT").errback do |e|
          if e.is_a? Net::IMAP::ByeResponseError
            # RFC 3501 says the server MUST send a BYE response and then close the connection.
            disconnect
            command.succeed e
          end
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

      def list(refname="", mailbox="*")
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

      def search(keys, charset=nil)
        search_internal(["SEARCH"], keys, charset)
      end

      def uid_search(keys, charset=nil)
        search_internal(["UID SEARCH"], keys, charset)
      end

      # SORT and THREAD (like SEARCH) from http://tools.ietf.org/search/rfc5256
      def sort(sort_keys, search_keys, charset=nil)
        search_internal(["SORT", sort_keys], search_keys, charset)
      end

      def uid_sort
        search_internal(["UID SORT", sort_keys], search_keys, charset)
      end

      def thread(algorithm, search_keys, charset=nil)
        search_internal(["THREAD", algorithm], search_keys, charset)
      end

      def uid_thread
        search_internal(["UID THREAD", algorithm], search_keys, charset)
      end

      def fetch(seq, attr)
        fetch_internal("FETCH", seq, attr)
      end

      def uid_fetch(seq, attr)
        fetch_internal("UID FETCH", seq, attr)
      end

      def store(seq, name, value)
        store_internal("STORE", seq, name, value)
      end

      def uid_store(seq, name, value)
        store_internal("UID STORE", seq, name, value)
      end

      # The IDLE command allows you to wait for any untagged responses
      # that give status updates about the contents of a mailbox.
      #
      # Until you call stop on the idler, no further commands can be sent
      # over this connection.
      #
      # idler = connection.idle do |untagged_response|
      #   case untagged_response.name
      #   #...
      #   end
      # end
      #
      # EM.timeout(60) { idler.stop }
      #
      def idle(&block)
        @connection.send_idle_command &block
      end

      def receive_untagged_responses(&block)
        @connection.receive_untagged_responses(&block)
      end

      private
      
      # The callback of a Command returns both a tagged response,
      # and optionally a list of untagged responses that were
      # generated at the same time.
      def tagged_response(cmd, *args)
        send_command(cmd, *args)
      end

      def one_data_response(cmd, *args)
        send_command(cmd, *args).transform{ |response| untagged_responses[cmd].pop }
      end

      def multi_data_response(*command)
        send_command(*command).transform{ |response| untagged_responses.delete(cmd) }
      end

      def send_command(cmd, *args)
        @connection.send_command(cmd, *args)
      end

      # From Net::IMAP
      def fetch_internal(cmd, set, attr)
        case attr
        when String then
          attr = RawData.new(attr)
        when Array then
          attr = attr.map { |arg|
            arg.is_a?(String) ? RawData.new(arg) : arg
          }
        end

        multi_data_response(cmd)
      end

      def store_internal(cmd, set, attr, flags)
        if attr.instance_of?(String)
          attr = RawData.new(attr)
        end
        send_command(cmd, Net::IMAP::MessageSet.new(set), attr, flags).transform do |response|
          untagged_responses.delete 'FETCH'
        end
      end

      # From Net::IMAP
      def search_internal(command, keys, charset)
        if keys.instance_of?(String)
          keys = [Net::IMAP::RawData.new(keys)]
        else
          normalize_searching_criteria(keys)
        end
        if charset
          one_data_response *(command + ["CHARSET", charset] + keys)
        else
          one_data_response *(command + keys)
        end
      end

      # From Net::IMAP
      def normalize_searching_criteria(keys)
        keys.collect! do |i|
          case i
          when -1, Range, Array
            Net::IMAP::MessageSet.new(i)
          else
            i
          end
        end
      end
    end
  end
end

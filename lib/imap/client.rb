module EventMachine
  module Imap
    # TODO: Anything that accepts or returns a mailbox name should have UTF7 support.
    class Client
      include EM::Deferrable
      DG.enhance!(self)

      include Imap::Authenticators

      def initialize(connection)
        @connection = connection.errback{ |e| fail e }.callback{ |response| succeed response }
      end

      def disconnect
        @connection.close_connection
      end

      ## 6.1 Client Commands - Any State.

      # Ask the server which capabilities it supports.
      #
      # Succeeds with an array of capabilities.
      #
      def capability
        one_data_response("CAPABILITY").transform{ |response| response.data }
      end

      # Actively do nothing.
      #
      # This is useful as a keep-alive, or to persuade the server to send
      # any untagged responses your listeners would like.
      #
      # Succeeds with nil.
      #
      def noop
        tagged_response("NOOP")
      end

      # Logout and close the connection.
      #
      # This will cause any other listeners or commands that are still active
      # to fail, and render this client unusable.
      #
      def logout
        command = tagged_response("LOGOUT").errback do |e|
          if e.is_a? Net::IMAP::ByeResponseError
            # RFC 3501 says the server MUST send a BYE response and then close the connection.
            disconnect
            command.succeed
          end
        end
      end

      ## 6.2 Client Commands - Not Authenticated State

      # This would start tls negotiations, until this is implemented,
      # simply pass true as the first parameter to EM::Imap.connect.
      #
      def starttls
        raise NotImplementedError
      end

      # Authenticate using a custom authenticator.
      #
      # By default there are two custom authenticators available:
      #
      #  'LOGIN', username, password
      #  'CRAM-MD5', username, password (see RFC 2195)
      #
      # Though you can add new mechanisms using EM::Imap.add_authenticator,
      # see for example the gmail_xoauth gem.
      #  
      def authenticate(auth_type, *args)
        # Extract these first so that any exceptions can be raised
        # before the command is created.
        auth_type = auth_type.upcase
        auth_handler = authenticator(auth_type, *args)

        tagged_response('AUTHENTICATE', auth_type).tap do |command|
          @connection.send_authentication_data(auth_handler, command)
        end
      end

      # Authenticate with a username and password.
      #
      # NOTE: this SHOULD only work over a tls connection.
      #
      # If the password is wrong, the command will fail with a
      # Net::IMAP::NoResponseError.
      #
      def login(username, password)
        tagged_response("LOGIN", username, password)
      end

      ## 6.3 Client Commands - Authenticated State

      # Select a mailbox for performing commands against. 
      #
      # This will generate untagged responses that you can subscribe to
      # by adding a block to the listener with .listen, for more detail,
      # see RFC 3501, section 6.3.1.
      #
      def select(mailbox)
        tagged_response("SELECT", to_utf7(mailbox))
      end

      # Select a mailbox for performing read-only commands.
      #
      # This is exactly the same as select, except that no operation may
      # cause a change to the state of the mailbox or its messages.
      #
      def examine(mailbox)
        tagged_response("EXAMINE", to_utf7(mailbox))
      end

      # Create a new mailbox with the given name.
      #
      def create(mailbox)
        tagged_response("CREATE", to_utf7(mailbox))
      end

      # Delete the mailbox with this name.
      #
      def delete(mailbox)
        tagged_response("DELETE", to_utf7(mailbox))
      end

      # Rename the mailbox with this name.
      #
      def rename(oldname, newname)
        tagged_response("RENAME", to_utf7(oldname), to_utf7(newname))
      end

      # Add this mailbox to the list of subscribed mailboxes.
      #
      def subscribe(mailbox)
        tagged_response("SUBSCRIBE", to_utf7(mailbox))
      end

      # Remove this mailbox from the list of subscribed mailboxes.
      #
      def unsubscribe(mailbox)
        tagged_response("UNSUBSCRIBE", to_utf7(mailbox))
      end

      # List all available mailboxes.
      #
      # @param: refname, an optional context in which to list.
      # @param: mailbox, a  which mailboxes to return.
      #
      # Succeeds with a list of Net::IMAP::MailboxList structs, each of which has:
      #   .name, the name of the mailbox (in UTF8)
      #   .delim, the delimeter (normally "/")
      #   .attr, A list of attributes, e.g. :Noselect, :Haschildren, :Hasnochildren.
      #
      def list(refname="", pattern="*")
        list_internal("LIST", refname, pattern)
      end

      # List all subscribed mailboxes.
      #
      # This is the same as list, but restricted to mailboxes that have been subscribed to.
      #
      def lsub(refname, pattern)
        list_internal("LSUB", refname, pattern)
      end

      # Get the status of a mailbox.
      #
      # This provides similar information to the untagged responses you would
      # get by running SELECT or EXAMINE without doing so.
      #
      # @param mailbox, a mailbox to query
      # @param attrs, a list of attributes to query for (valid values include
      #        MESSAGES, RECENT, UIDNEXT, UIDVALIDITY and UNSEEN — RFC3501#6.3.8)
      #
      # Succeeds with a hash of attribute name to value returned by the server.
      #
      def status(mailbox, attrs)
        one_data_response("STATUS", to_utf7(mailbox), attrs).transform do |response|
          response.data.attr
        end
      end

      # Add a message to the mailbox.
      #
      # @param mailbox, the mailbox to add to,
      # @param message, the full text (including headers) of the email to add.
      # @param flags, A list of flags to set on the email.
      # @param date_time, The time to be used as the internal date of the email.
      #
      # The tagged response with which this command succeeds contains the UID
      # of the email that was appended.
      #
      def append(mailbox, message, flags=nil, date_time=nil)
        args = [to_utf7(mailbox)]
        args << flags if flags
        args << date_time if date_time
        args << Net::IMAP::Literal.new(message)
        tagged_response("APPEND", *args)
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
        send_command("IDLE").listen(&block).tap do |command|
          @connection.prepare_idle_continuation(command)
        end
      end

      def add_response_handler(&block)
        @connection.add_response_handler(&block)
      end

      private

      # Convert a string to the modified UTF-7 required by IMAP for mailbox naming.
      # See RFC 3501 Section 5.1.3 for more information.
      #
      def to_utf7(text)
        Net::IMAP.encode_utf7(text)
      end

      # Convert a string from the modified UTF-7 required by IMAP for mailbox naming.
      # See RFC 3501 Section 5.1.3 for more information.
      #
      def to_utf8(text)
        Net::IMAP.decode_utf7(text)
      end
      
      # Send a command that should return a deferrable that succeeds with
      # a tagged_response.
      #
      def tagged_response(cmd, *args)
        # We put in an otherwise unnecessary transform to hide the listen
        # method from callers for consistency with other types of responses.
        send_command(cmd, *args)
      end

      # Send a command that should return a deferrable that succeeds with
      # a single untagged response with the same name as the command.
      #
      def one_data_response(cmd, *args)
        multi_data_response(cmd, *args).transform do |untagged_responses|
          untagged_responses.last
        end
      end

      # Send a command that should return a deferrable that succeeds with
      # multiple untagged responses with the same name as the command.
      #
      def multi_data_response(cmd, *args)
        collect_untagged_responses(cmd, cmd, *args)
      end

      # Send a command that should return a deferrable that succeeds with
      # multiple untagged responses with the given name.
      #
      def collect_untagged_responses(name, *command)
        untagged_responses = []

        send_command(*command).listen do |response|
          if response.is_a?(Net::IMAP::UntaggedResponse) && response.name == name
            untagged_responses << response

          # If we observe another tagged response completeing, then we can be
          # sure that the previous untagged responses were not relevant to this command.
          elsif response.is_a?(Net::IMAP::TaggedResponse)
            untagged_responses = []

          end
        end.transform do |tagged_response|
          untagged_responses
        end
      end

      def send_command(cmd, *args)
        @connection.send_command(cmd, *args)
      end

      # Extract more useful data from the LIST and LSUB commands, see #list for details. 
      def list_internal(cmd, refname, pattern)
        multi_data_response(cmd, to_utf7(refname), to_utf7(pattern)).transform do |untagged_responses|
          untagged_responses.map(&:data).map do |data|
            data.dup.tap do |new_data|
              new_data.name = to_utf8(data.name)
            end
          end
        end
      end

      # From Net::IMAP
      def fetch_internal(cmd, set, attr)
        case attr
        when String then
          attr = Net::IMAP::RawData.new(attr)
        when Array then
          attr = attr.map { |arg|
            arg.is_a?(String) ? Net::IMAP::RawData.new(arg) : arg
          }
        end

        multi_data_response(cmd, set, attr)
      end

      def store_internal(cmd, set, attr, flags)
        if attr.instance_of?(String)
          attr = Net::IMAP::RawData.new(attr)
        end
        collect_untagged_responses('FETCH', cmd, *args)
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

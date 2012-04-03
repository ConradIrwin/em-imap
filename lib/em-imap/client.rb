module EventMachine
  module IMAP
    # TODO: Anything that accepts or returns a mailbox name should have UTF7 support.
    class Client
      include EM::Deferrable
      DG.enhance!(self)

      include IMAP::Authenticators

      def initialize(host, port, usessl=false)
        @connect_args=[host, port, usessl]
      end

      def connect
        @connection = EM::IMAP::Connection.connect(*@connect_args)
        @connection.errback{ |e| fail e }.
                    callback{ |*args| succeed *args }

        @connection.hello_listener
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
      # simply pass true as the first parameter to EM::IMAP.connect.
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
      # Though you can add new mechanisms using EM::IMAP.add_authenticator,
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
      def status(mailbox, attrs=['MESSAGES', 'RECENT', 'UIDNEXT', 'UIDVALIDITY', 'UNSEEN'])
        attrs = [attrs] if attrs.is_a?(String)
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
      
      # Checkpoint the current mailbox.
      #
      # This is an implementation-defined operation, when in doubt, NOOP
      # should be used instead.
      #
      def check
        tagged_response("CHECK")
      end

      # Unselect the current mailbox.
      #
      # As a side-effect, permanently removes any messages that have the
      # \Deleted flag. (Unless the mailbox was selected using the EXAMINE,
      # in which case no side effects occur).
      #
      def close
        tagged_response("CLOSE")
      end
      
      # Permanently remove any messages with the \Deleted flag from the current
      # mailbox.
      #
      # Succeeds with a list of message sequence numbers that were deleted.
      #
      # NOTE: If you're planning to EXPUNGE and then SELECT a new mailbox,
      # and you don't care which messages are removed, consider using
      # CLOSE instead.
      #
      def expunge
        multi_data_response("EXPUNGE").transform do |untagged_responses|
          untagged_responses.map(&:data)
        end
      end

      # Search for messages in the current mailbox.
      #
      # @param *args The arguments to search, these can be strings, arrays or ranges
      #              specifying sub-groups of search arguments or sets of messages.
      #
      #              If you want to use non-ASCII characters, then the first two
      #              arguments should be 'CHARSET', 'UTF-8', though not all servers
      #              support this.
      #
      # @succeed A list of message sequence numbers.
      #
      def search(*args)
        search_internal("SEARCH", *args)
      end

      # The same as search, but succeeding with a list of UIDs not sequence numbers.
      #
      def uid_search(*args)
        search_internal("UID SEARCH", *args)
      end

      # SORT and THREAD (like SEARCH) from http://tools.ietf.org/search/rfc5256
      #
      def sort(sort_keys, *args)
        raise NotImplementedError
      end

      def uid_sort(sort_keys, *args)
        raise NotImplementedError
      end

      def thread(algorithm, *args)
        raise NotImplementedError
      end

      def uid_thread(algorithm, *args)
        raise NotImplementedError
      end

      # Get the contents of, or information about, a message.
      # 
      # @param seq, a message or sequence of messages (a number, a range or an array of numbers)
      # @param attr, the name of the attribute to fetch, or a list of attributes.
      #
      # Possible attribute names (see RFC 3501 for a full list):
      #
      #  ALL: Gets all header information,
      #  FULL: Same as ALL with the addition of the BODY,
      #  FAST: Same as ALL without the message envelope.
      #
      #  BODY: The body
      #  BODY[<section>] A particular section of the body
      #  BODY[<section>]<<start>,<length>> A substring of a section of the body.
      #  BODY.PEEK: The body (but doesn't change the \Recent flag)
      #  FLAGS: The flags
      #  INTERNALDATE: The internal date
      #  UID: The unique identifier
      #
      def fetch(seq, attr="FULL")
        fetch_internal("FETCH", seq, attr)
      end

      # The same as fetch, but keyed of UIDs instead of sequence numbers.
      #
      def uid_fetch(seq, attr="FULL")
        fetch_internal("UID FETCH", seq, attr)
      end

      # Update the flags on a message.
      #
      # @param seq, a message or sequence of messages (a number, a range, or an array of numbers)
      # @param name, any of FLAGS FLAGS.SILENT, replace the flags
      #                     +FLAGS, +FLAGS.SILENT, add the following flags
      #                     -FLAGS, -FLAGS.SILENT, remove the following flags
      #             The .SILENT versions suppress the server's responses.
      # @param value, a list of flags (symbols)
      #
      def store(seq, name, value)
        store_internal("STORE", seq, name, value)
      end

      # The same as store, but keyed off UIDs instead of sequence numbers.
      #
      def uid_store(seq, name, value)
        store_internal("UID", "STORE", seq, name, value)
      end

      # Copy the specified messages to another mailbox.
      #
      def copy(seq, mailbox)
        tagged_response("COPY", Net::IMAP::MessageSet.new(seq), to_utf7(mailbox))
      end

      # The same as copy, but keyed off UIDs instead of sequence numbers.
      #
      def uid_copy(seq, mailbox)
        tagged_response("UID", "COPY", Net::IMAP::MessageSet.new(seq), to_utf7(mailbox))
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
        send_command("IDLE").tap do |command|
          @connection.prepare_idle_continuation(command)
          command.listen(&block) if block_given?
        end
      end

      def add_response_handler(&block)
        @connection.add_response_handler(&block)
      end

      private

      # Decode a string from modified UTF-7 format to UTF-8.
      #
      # UTF-7 is a 7-bit encoding of Unicode [UTF7].  IMAP uses a
      # slightly modified version of this to encode mailbox names
      # containing non-ASCII characters; see [IMAP] section 5.1.3.
      #
      # Net::IMAP does _not_ automatically encode and decode
      # mailbox names to and from utf7.
      def to_utf8(s)
        return force_encoding(s.gsub(/&(.*?)-/n) {
          if $1.empty?
            "&"
          else
            base64 = $1.tr(",", "/")
            x = base64.length % 4
            if x > 0
              base64.concat("=" * (4 - x))
            end
            base64.unpack("m")[0].unpack("n*").pack("U*")
          end
        }, "UTF-8")
      end

      # Encode a string from UTF-8 format to modified UTF-7.
      def to_utf7(s)
        return force_encoding(force_encoding(s, 'UTF-8').gsub(/(&)|([^\x20-\x7e]+)/u) {
          if $1
            "&-"
          else
            base64 = [$&.unpack("U*").pack("n*")].pack("m")
            "&" + base64.delete("=\n").tr("/", ",") + "-"
          end
        }, "ASCII-8BIT")
      end

      # FIXME: I haven't thought through the ramifications of this yet.
      def force_encoding(s, encoding)
        if s.respond_to?(:force_encoding)
          s.force_encoding(encoding)
        else
          s
        end
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

        set = Net::IMAP::MessageSet.new(set)

        collect_untagged_responses('FETCH', cmd, set, attr).transform do |untagged_responses|
          untagged_responses.map(&:data)
        end
      end

      # Ensure that the flags are symbols, and that the message set is a message set.
      def store_internal(cmd, set, attr, flags)
        flags = flags.map(&:to_sym)
        set = Net::IMAP::MessageSet.new(set)
        collect_untagged_responses('FETCH', cmd, set, attr, flags).transform do |untagged_responses|
          untagged_responses.map(&:data)
        end
      end

      def search_internal(command, *args)
        collect_untagged_responses('SEARCH', command, *normalize_search_criteria(args)).transform do |untagged_responses|
          untagged_responses.last.data
        end
      end

      # Recursively find all the message sets in the arguments and convert them so that
      # Net::IMAP can serialize them.
      def normalize_search_criteria(args)
        args.map do |arg|
          case arg
          when "*", -1, Range
            Net::IMAP::MessageSet.new(arg)
          when Array
            if arg.inject(true){|bool,item| bool and (item.is_a?(Integer) or item.is_a?(Range))}
              Net::IMAP::MessageSet.new(arg)
            else
              normalize_search_criteria(arg)
            end
          else
            arg
          end
        end
      end
    end
  end
end

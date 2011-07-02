module EventMachine
  module IMAP
    # Intercepts the receive_data event and generates receive_response events
    # with parsed data.
    module ResponseParser
      def post_init
        super
        @parser = Net::IMAP::ResponseParser.new
        @buffer = ""
      end

      # This is a translation of Net::IMAP#get_response
      def receive_data(data)
        @buffer += data

        until @buffer.empty?

          eol = @buffer.index(CRLF)
          
          # Include IMAP literals on the same line.
          # The format for a literal is "{8}\r\n........"
          # so the size would be at the end of what we thought was the line.
          # We then skip over that much, and try looking for the next newline.
          # (The newline after a literal is the end of the actual line,
          # there's no termination marker for literals).
          while eol && @buffer[0, eol][/\{(\d+)\}\z/]
            eol = @buffer.index(CRLF, eol + CRLF.size + $1.to_i)
          end

          # The current line is not yet complete, wait for more data.
          return unless eol

          line = @buffer.slice!(0, eol + CRLF.size)

          receive_response parse(line)
        end
      end

      # Callback used by receive data.
      def receive_response(response); end

      # Callback used if something goes wrong.
      def fail_all(error); end

      private

      def parse(line)
        @parser.parse(line)
      rescue Net::IMAP::ResponseParseError => e
        fail_all e
      end
    end
  end
end


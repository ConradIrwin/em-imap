module EventMachine
  module IMAP
    class Formatter

      # A placeholder so that the command sender knows to treat literal strings specially
      class Literal < Struct.new(:str); end

      # Format the data to be sent into strings and literals, and call the block
      # for each token to be sent.
      #
      # @param data   The data to format,
      # @param &block The callback, which will be called with a number of strings and
      #               EM::IMAP::Formatter::Literal instances.
      #
      # NOTE: The block is responsible for handling any network-level concerns, such
      # as sending literals only with permission.
      #
      def self.format(data, &block)
        new(&block).send_data(data)
      end

      def initialize(&block)
        @block = block
      end

      def put_string(str)
        @block.call str
      end

      def send_literal(str)
        @block.call Literal.new(str)
      end

      # The remainder of the code in this file is directly from Net::IMAP.
      # Copyright (C) 2000  Shugo Maeda <shugo@ruby-lang.org>
      def send_data(data)
        case data
        when nil
          put_string("NIL")
        when String
          send_string_data(data)
        when Integer
          send_number_data(data)
        when Array
          send_list_data(data)
        when Time
          send_time_data(data)
        when Symbol
          send_symbol_data(data)
        when EM::IMAP::Command
          send_command(data)
        else
          data.send_data(self)
        end
      end

      def send_command(cmd)
        put_string cmd.tag
        put_string " "
        put_string cmd.cmd
        cmd.args.each do |i|
          put_string " "
          send_data(i)
        end
        put_string "\r\n"
      end

      def send_string_data(str)
        case str
        when ""
          put_string('""')
        when /[\x80-\xff\r\n]/n
          # literal
          send_literal(str)
        when /[(){ \x00-\x1f\x7f%*"\\]/n
          # quoted string
          send_quoted_string(str)
        else
          put_string(str)
        end
      end

      def send_quoted_string(str)
        put_string('"' + str.gsub(/["\\]/n, "\\\\\\&") + '"')
      end

      def send_number_data(num)
        if num < 0 || num >= 4294967296
          raise Net::IMAP::DataFormatError, num.to_s
        end
        put_string(num.to_s)
      end

      def send_list_data(list)
        put_string("(")
        first = true
        list.each do |i|
          if first
            first = false
          else
            put_string(" ")
          end
          send_data(i)
        end
        put_string(")")
      end

      DATE_MONTH = %w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

      def send_time_data(time)
        t = time.dup.gmtime
        s = format('"%2d-%3s-%4d %02d:%02d:%02d +0000"',
                   t.day, DATE_MONTH[t.month - 1], t.year,
                   t.hour, t.min, t.sec)
        put_string(s)
      end

      def send_symbol_data(symbol)
        put_string("\\" + symbol.to_s)
      end

    end
  end
end

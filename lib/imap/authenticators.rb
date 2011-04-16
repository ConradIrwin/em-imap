module EventMachine
  # Makes Net::IMAP.add_authenticator accessible through EM::Imap and instances thereof.
  # Also provides the authenticator method to EM::Imap::Client to get authenticators
  # for use in the authentication exchange.
  #
  module Imap
    def self.add_authenticator(klass)
      Net::IMAP.add_authenticator(*args)
    end

    module Authenticators
      def add_authenticator(*args)
        EventMachine::Imap.add_authenticator(*args)
      end

      private

      def authenticator(type, *args)
        raise ArgumentError, "Unknown auth type - '#{type}'" unless imap_authenticators[type]
        imap_authenticators[type].new(*args)
      end

      def imap_authenticators
        Net::IMAP.send :class_variable_get, :@@authenticators
      end
    end
  end
end

module EventMachine
  # Makes Net::IMAP.add_authenticator accessible through EM::IMAP and instances thereof.
  # Also provides the authenticator method to EM::IMAP::Client to get authenticators
  # for use in the authentication exchange.
  #
  module IMAP
    def self.add_authenticator(*args)
      Net::IMAP.add_authenticator(*args)
    end

    module Authenticators
      def add_authenticator(*args)
        EventMachine::IMAP.add_authenticator(*args)
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

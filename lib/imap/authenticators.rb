module EventMachine
  module Imap
    # Support Net::IMAP compatible authenticators.
    module Authenticators
      def self.included(klass)
        def klass.add_authenticator(*args)
          Net::IMAP.add_authenticator(*args)
        end
      end

      def add_authenticator(*args)
        self.class.add_authenticator(*args)
      end

      private

      def authenticator(type, *args)
        raise ArgumentError "Unknown auth type - '#{type}'" unless imap_authenticators[type]
        imap_authenticators[type].new(*args)
      end

      def imap_authenticators
        Net::IMAP.send :class_variable_get, :@@authenticators
      end
    end
  end
end

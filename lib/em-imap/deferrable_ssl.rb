module EventMachine
  module IMAP

    # By default it's hard to tell when the SSL handshake has finished.
    # We thus wrap start_tls so that it returns a deferrable that will
    # tell us when it's done.
    module DeferrableSSL
      # Run a TLS handshake and return a deferrable that succeeds when it's
      # finished
      #
      # TODO: expose certificates so they can be verified.
      def start_tls
        unless @ssl_deferrable
          @ssl_deferrable = DG::blank
          bothback{ @ssl_deferrable.fail }
          super
        end
        @ssl_deferrable
      end

      # Hook into ssl_handshake_completed so that we know when to succeed
      # the deferrable we returned above.
      def ssl_handshake_completed
        @ssl_deferrable.succeed
        super
      end
    end
  end
end

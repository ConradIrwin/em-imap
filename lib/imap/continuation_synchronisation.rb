module EventMachine
  module Imap
    # The basic IMAP protocol is an unsynchronised exchange of lines,
    # however under some circumstances it is necessary to synchronise
    # so that the server acknowledges each item sent by the client.
    #
    # For example, this happens during authentication:
    #
    #  C: A0001 AUTHENTICATE LOGIN
    #  S: + 
    #  C: USERNAME
    #  S: +
    #  C: PASSWORD
    #  S: A0001 OK authenticated as USERNAME.
    #
    # And during the sending of literals:
    #
    #  C: A0002 SELECT {8}
    #  S: + continue
    #  C: All Mail
    #  S: A0002 OK
    #
    # In order to make this work this module allows part of the client
    # to block the outbound link while waiting for the continuation
    # responses that it is expecting.
    #
    module ContinuationSynchronisation

      def post_init
        super
        @awaiting_continuation = nil
      end

      # Pass all continuation responses to the block until further notice.
      #
      # Returns a deferrable which you should succeed or fail when you have
      # received all the continuations you need.
      def await_continuations(&block)
        ContinuationWaiter.new(block).tap do |waiter|
          when_not_awaiting_continuation do
            @awaiting_continuation = waiter.bothback{ @awaiting_continuation = nil }
          end
        end
      end

      # Pass any continuation response to the block that is expecting it.
      def receive_continuation(response)
        if awaiting_continuation?
          @awaiting_continuation.block.call response
        else
          fail_all Net::IMAP::ResponseParseError.new(response.raw_data)
        end
      end

      # Wait until the connection is not waiting for a continuation before
      # performing this block.
      #
      # If possible, the block will be executed immediately; if not it will
      # be added to a queue and executed whenever the queue has been emptied.
      #
      # Any previous items in the queue that wait on the connection will 
      def when_not_awaiting_continuation(&block)
        if awaiting_continuation?
          @awaiting_continuation.bothback{ when_not_awaiting_continuation(&block) }
        else
          yield
        end
      end

      def awaiting_continuation?
        !!@awaiting_continuation
      end
    end
  end
end

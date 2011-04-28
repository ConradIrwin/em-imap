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
    # TODO: This synchronisation mehcanism ought to be available standalone...
    module ContinuationSynchronisation

      def post_init
        super
        @awaiting_continuation = nil
        listen_for_continuation
      end

      def awaiting_continuation?
        !!@awaiting_continuation
      end

      # Pass all continuation responses to the block.
      #
      # Returns a deferrable which you should succeed when you have
      # received all the necessary continuations.
      def await_continuations(&block)
        Listener.new(&block).tap do |waiter|
          when_not_awaiting_continuation do
            @awaiting_continuation = waiter.stopback do
              @awaiting_continuation = nil
              waiter.succeed
            end
          end
        end
      end

      # Pass any continuation response to the block that is expecting it.
      def listen_for_continuation
        add_response_handler do |response|
          if response.is_a?(Net::IMAP::ContinuationRequest)
            if awaiting_continuation?
              @awaiting_continuation.receive_event response
            else
              fail Net::IMAP::ResponseParseError.new(response.raw_data)
            end
          end
        end
      end

      # Wait until the connection is not waiting for a continuation before
      # performing this block.
      #
      # If possible, the block will be executed immediately; if not it will
      # be added to a queue and executed whenever the queue has been emptied.
      #
      # Note that if a queued callback retakes the synchronisation lock then
      # all the later callbacks will be tranferred to the new queue.
      #
      def when_not_awaiting_continuation(&block)
        if awaiting_continuation?
          @awaiting_continuation.bothback{ when_not_awaiting_continuation(&block) }
        else
          yield
        end
      end
    end
  end
end

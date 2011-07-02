module EventMachine
  module IMAP
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
        listen_for_continuation
      end

      def awaiting_continuation?
        !!@awaiting_continuation
      end

      # Await further continuation responses from the server, and
      # pass them to the given block.
      #
      # As a side-effect causes when_not_awaiting_continuations to
      # queue further blocks instead of executing them immediately.
      #
      # NOTE: If there's currently a different block awaiting continuation
      # responses, this block will be added to its queue.
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

      # Add a single, permanent listener to the connection that forwards
      # continuation responses onto the currently awaiting block.
      def listen_for_continuation
        add_response_handler do |response|
          if response.is_a?(Net::IMAP::ContinuationRequest)
            if awaiting_continuation?
              @awaiting_continuation.receive_event response
            else
              fail_all Net::IMAP::ResponseError.new("Unexpected continuation response from server")
            end
          end
        end
      end

      # If nothing is listening for continuations from the server,
      # execute the block immediately.
      # 
      # Otherwise add the block to the queue.
      #
      # When we have replied to the server's continuation response,
      # the queue will be emptied in-order.
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

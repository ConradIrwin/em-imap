module EventMachine
  module Imap
    # A Listener is a cancellable subscriber to an event stream, they are used
    # to provide control-flow abstraction throughout em-imap.
    #
    # They can be thought of as a deferrable with two internal phases:
    #
    #   deferrable: create |-------------------------------> [succeed/fail]
    #   listener:   create |---[listening]----> [stop]-----> [succeed/fail]
    #
    # A stopback may call succeed or fail immediately, or after performing necessary cleanup.
    #
    # There are several hooks to which you can subscribe:
    #
    #  #listen(&block): Each time .receive_event is called, the block will
    #  be called.
    #
    #  #stopback(&block): When someone calls .stop on the listener, this block
    #  will be called.
    #
    #  #callback(&block), #errback(&block), #bothback(&block): Inherited from
    #  deferrables (and enhanced by deferrable gratification).
    #
    #
    # And the corresponding methods for sending messages to subscribers:
    #
    #  #receive_event(*args): Passed onto blocks registered by listen.
    #
    #  #stop(*args): Calls all the stopbacks.
    #  
    #  #succeed(*args), #fail(*args): Inherited from deferrables, calls stop
    #  if that hasn't yet been called.
    #
    # In normal usage the library managing the Listeners will call
    # receive_event, # succeed and fail; while the program using the library
    # will call stop.  By the same token, normally the program using the
    # library will register events on listen, callback and errback, but the
    # library will use stopback.
    #
    # NOTE: While succeed and fail will call the stopbacks if necessary, stop
    # will not succeed or fail the deferrable, that is the job of one of the
    # stopbacks or external circumstance.
    #
    module ListeningDeferrable
      include EM::Deferrable
      DG.enhance!(self)

      # Register a block to be called when receive_event is called.
      def listen(&block)
        listeners << block
        self
      end

      # Pass arguments onto any blocks registered with listen.
      def receive_event(*args, &block)
        listeners.each{ |l| l.call *args, &block }
      end

      # Register a block to be called when the ListeningDeferrable is stopped.
      def stopback(&block)
        stop_deferrable.callback &block
        self
      end

      # Initiate shutdown.
      def stop(*args, &block)
        stop_deferrable.succeed *args, &block
      end

      def set_deferred_status(*args, &block)
        # Ensure that the ListeningDeferrable is stopped first
        stop
        super
      end

      private
      def listeners; @listeners ||= []; end
      def stop_deferrable; @stop_deferrable ||= DefaultDeferrable.new; end
    end

    class Listener
      include ListeningDeferrable
      def initialize(&block)
        listen &block if block_given?
      end
    end
  end
end

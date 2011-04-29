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
    #  #succeed(*args), #fail(*args): Inherited from deferrables.
    #
    #
    # NOTE: It is normally the case that the code "listening" to the listener
    # will call stop, and that the code sending events to the listener will
    # call succeed or fail.
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

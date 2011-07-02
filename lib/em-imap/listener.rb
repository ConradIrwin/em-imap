module EventMachine
  module IMAP
    # A Listener is a cancellable subscriber to an event stream, they are used
    # to provide control-flow abstraction throughout em-imap.
    #
    # They can be thought of as a deferrable with two internal phases:
    #
    #   deferrable: create |-------------------------------> [succeed/fail]
    #   listener:   create |---[listening]----> [stop]-----> [succeed/fail]
    #
    # A stopback may call succeed or fail immediately, or after performing
    # necessary cleanup.
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
    # Listeners are defined in such a way that it's most natural to create them
    # from deep within a library, and return them to the original caller via
    # layers of abstraction.
    #
    # To this end, they also have a .transform method which can be used to
    # create a new listener that acts the same as the old listener, but which
    # succeeds with a different return value. The call to .stop is propagated
    # from the new listener to the old, but calls to .receive_event, .succeed
    # and .fail are propagated from the old to the new.
    #
    # This slightly contrived example shows how listeners can be used with three
    # levels of abstraction juxtaposed:
    #
    # def receive_characters
    #   Listener.new.tap do |listener|
    #
    #     continue = true
    #     listener.stopback{ continue = false }
    #
    #     EM::next_tick do
    #       while continue
    #         if key = $stdin.read(1)
    #           listener.receive_event key
    #         else
    #           continue = false
    #           listener.fail EOFError.new
    #         end
    #       end
    #       listener.succeed
    #     end
    #   end
    # end
    #
    # def get_line
    #   buffer = ""
    #   listener = receive_characters.listen do |key|
    #     buffer << key
    #     listener.stop if key == "\n"
    #   end.transform do
    #     buffer
    #   end
    # end
    #
    # EM::run do
    #   get_line.callback do |line|
    #     puts "DONE: #{line}"
    #   end.errback do |e|
    #     puts [e] + e.backtrace
    #   end.bothback do
    #     EM::stop
    #   end
    # end
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
        # NOTE: Take a clone of listeners, so any listeners added by listen
        # blocks won't receive these events.
        listeners.clone.each{ |l| l.call *args, &block }
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

      # A re-implementation of DG::Combinators#transform.
      #
      # The returned listener will succeed at the same time as this listener,
      # but the value with which it succeeds will have been transformed using
      # the given block. If this listener fails, the returned listener will
      # also fail with the same arguments.
      #
      # In addition, any events that this listener receives will be forwarded
      # to the new listener, and the stop method of the new listener will also
      # stop the existing listener.
      #
      # NOTE: This does not affect the implementation of bind! which still
      # returns a normal deferrable, not a listener.
      #
      def transform(&block)
        Listener.new.tap do |listener|
          self.callback do |*args|
            listener.succeed block.call(*args)
          end.errback do |*args|
            listener.fail *args
          end.listen do |*args|
            listener.receive_event *args
          end

          listener.stopback{ self.stop }
        end
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

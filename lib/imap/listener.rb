module EventMachine
  module Imap
    # A Listener is a cancellable subscriber to an event stream, they
    # are used to provide control-flow abstraction throughout em-imap.
    #
    # There are four types of callback that you can register on a Listener:
    #
    #  .listen(&block)   Each time .receive_event is called, the block will
    #                    also be called.
    #
    # *.stopback(&block) When someone calls .stop on the listener, this block
    #                    will be called.
    #
    #  .callback(&block) When no more events will be received, and all internal
    #                    state was successfully cleaned up, this block will be
    #                    called.
    #
    #  .errback(&block)  When no more events will be received, because of an
    #                    error, the block will be called.
    #
    # NOTE: Listeners are deferrables enhanced by Deferrable Gratification, so
    # there's also a .bothback method inherited from there.
    #
    # In normal usage, only the library that creates Listeners will need .stopback,
    # programs using the library should do whatever they will at the same time as
    # they call stop.
    #
    # There are four corresponding ways of firing events at a Listener:
    #
    # *.receive_event(*args) Passed onto blocks registered by listen.
    #
    #  .stop(*args)          Calls all the stopbacks, and prevents any further
    #                        .receive_event calls from reaching the .listen
    #                        blocks.
    #  
    # *.succeed(*args)       Calls all the callbacks, and if .stop was not
    #                        called previously, calls .stop.
    #
    # *.fail(*args)          Calls all the errbacks, and if .stop was not called
    #                        previously, calls .stop.
    #
    # In normal usage, the library that creates the Listener is responsible for calling
    #  .receive_event, .succeed, and .fail, and the program using the library
    #  is responsible for calling .stop.
    #
    class Listener
      include EM::Deferrable
      DG.enhance!(self)

      def initialize(&block)
        @stop_deferrable = DefaultDeferrable.new
        @listeners = []
        bothback &method(:stop)
        listen &block if block_given?
      end

      def listen(&block)
        tap{ @listeners << block }
      end

      def stopback(*args, &block)
        tap{ @stop_deferrable.callback *args, &block }
      end

      def stop(*args, &block)
        @stopped = true
        @stop_deferrable.succeed *args, &block
      end

      def receive_event(*args, &block)
        @listeners.each{ |l| l.call *args, &block } unless @stopped
      end
    end
  end
end

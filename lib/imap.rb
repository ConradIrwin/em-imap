require 'net/imap'

require 'rubygems'
require 'eventmachine'
require 'deferrable_gratification'

$:.unshift File.dirname( __FILE__ )
require 'imap/listener'
require 'imap/continuation_synchronisation'
require 'imap/command_sender'
require 'imap/response_parser'
require 'imap/connection'

require 'imap/authenticators'
require 'imap/client'
$:.shift

module EventMachine
  module Imap
    def self.connect(host, port, ssl=false)
      conn = EventMachine.connect(host, port, EventMachine::Imap::Connection)
      conn.start_tls if ssl
      Client.new(conn)
    end

    class Command < Struct.new(:tag, :cmd, :args)
      include EventMachine::Deferrable
      DG.enhance! self
    end

    class IdleCommand < Command
      def initialize(*args, &block)
        super(*args)
        @done = block
      end

      def done(*args, &block)
        puts "Doning"
        @done.call(*args, &block)
        puts "DONE"
      end
    end

    class ContinuationWaiter < Struct.new(:block)
      include EventMachine::Deferrable
      DG.enhance! self
    end
  end
end

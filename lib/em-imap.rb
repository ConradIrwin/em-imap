require 'net/imap'
require 'set'

require 'rubygems'
require 'eventmachine'
require 'deferrable_gratification'

$:.unshift File.dirname( __FILE__ )
require 'em-imap/listener'
require 'em-imap/continuation_synchronisation'
require 'em-imap/formatter'
require 'em-imap/command_sender'
require 'em-imap/response_parser'
require 'em-imap/connection'

require 'em-imap/authenticators'
require 'em-imap/client'
$:.shift

module EventMachine
  module IMAP
    # Connect to the specified IMAP server, using ssl if applicable.
    #
    # Returns a deferrable that will succeed or fail based on the
    # success of the connection setup phase.
    #
    def self.connect(host, port, ssl=false)
      Client.new(EventMachine::IMAP::Connection.connect(host, port, ssl))
    end

    def self.new(host, port, ssl=false)
      Client.new(host, port, ssl)
    end

    class Command < Listener
      attr_accessor :tag, :cmd, :args
      def initialize(tag, cmd, args=[], &block)
        super(&block)
        self.tag = tag
        self.cmd = cmd
        self.args = args
      end
    end
  end
end

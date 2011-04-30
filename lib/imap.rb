require 'net/imap'
require 'set'

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
    # Connect to the specified IMAP server, using ssl if applicable.
    #
    # Returns a deferrable that will succeed or fail based on the
    # success of the connection setup phase.
    #
    def self.connect(host, port, ssl=false)
      Client.new(EventMachine::Imap::Connection.connect(host, port, ssl))
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

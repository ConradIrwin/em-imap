require 'spec_helper'

describe EM::IMAP::CommandSender do

  before :each do
    @command_sender = Class.new(EMStub) do
      include EM::IMAP::Connection
    end.new
  end

  describe "#send_authentication_data" do

    before :each do
      @authenticator = Class.new do
        def process; end
      end.new

      @command = EM::IMAP::Command.new("AUTHENTICATE", "XDUMMY")

      @command_sender.send_authentication_data(@authenticator, @command)
    end

    it "should notify the authenticator when the server sends a continuation" do
      @authenticator.should_receive(:process).with("")
      @command_sender.receive_data "+ \r\n"
    end
    
    # CRAM-MD5 example from http://tools.ietf.org/html/rfc2195
    it "should pass data to the authenticator via base64 decode" do
      @authenticator.should_receive(:process).with("<1896.697170952@postoffice.reston.mci.net>")
      @command_sender.receive_data "+ PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+\r\n"
    end

    it "should pass data back to the server via base64 encode" do
      @authenticator.should_receive(:process).with("<1896.697170952@postoffice.reston.mci.net>").and_return("tim b913a602c7eda7a495b4e6e7334d3890")
      @command_sender.should_receive(:send_data).with("dGltIGI5MTNhNjAyYzdlZGE3YTQ5NWI0ZTZlNzMzNGQzODkw\r\n")

      @command_sender.receive_data "+ PDE4OTYuNjk3MTcwOTUyQHBvc3RvZmZpY2UucmVzdG9uLm1jaS5uZXQ+\r\n"
    end

    # S/KEY example from http://tools.ietf.org/html/rfc1731
    it "should do both of the above multiple times" do
      @authenticator.should_receive(:process).with("").and_return("morgan")
      @command_sender.should_receive(:send_data).with("bW9yZ2Fu\r\n")
      @command_sender.receive_data "+ \r\n"

      @authenticator.should_receive(:process).with("95 Qa58308").and_return("FOUR MANN SOON FIR VARY MASH")
      @command_sender.should_receive(:send_data).with("Rk9VUiBNQU5OIFNPT04gRklSIFZBUlkgTUFTSA==\r\n")
      @command_sender.receive_data "+ OTUgUWE1ODMwOA==\r\n"
    end

    it "should stop blocking the connection if the server bails" do
      lambda {
        @command.fail Net::IMAP::NoResponseError.new
      }.should change{
        @command_sender.awaiting_continuation?
      }.from(true).to(false)
    end

    it "should stop blocking the connection when the command succeeds" do
      lambda {
        @command.succeed
      }.should change{
        @command_sender.awaiting_continuation?
      }.from(true).to(false)
    end

  end

  describe "#send_literal" do
    before :each do
      @command = EM::IMAP::Command.new("RUBY0001", "SELECT", ["AHLO"])
    end

    it "should initially only send the size" do
      @command_sender.should_receive(:send_data).with("{4}\r\n")
      @command_sender.send_literal "AHLO", @command
    end

    it "should send the remainder after the continuation response" do
      @command_sender.should_receive(:send_data).with("{4}\r\n")
      @command_sender.send_literal "AHLO", @command
      @command_sender.should_receive(:send_data).with("AHLO")
      @command_sender.receive_data "+ Continue\r\n"
    end

    it "should pause the sending of all the other literals" do
      @command_sender.should_receive(:send_data).with("SELECT {4}\r\n")
      @command_sender.send_string "SELECT ", @command
      @command_sender.send_literal "AHLO", @command
      @command_sender.send_string "\r\n", @command
      @command_sender.should_receive(:send_data).with("AHLO")
      @command_sender.should_receive(:send_data).with("\r\n")
      @command_sender.receive_data "+ Continue\r\n"
    end
  end

  describe "#send_command_object" do
    before :each do
      @bomb = Object.new
      def @bomb.send_data(connection)
        raise "bomb"
      end
    end

    it "should raise errors if the command cannot be serialized" do
      lambda {
        @command_sender.send_command_object(EM::IMAP::Command.new("RUBY0001", "IDLE", [@bomb]))
      }.should raise_exception "bomb"
    end

    it "should raise errors even if the unserializable object is after a literal" do
      lambda {
        @command_sender.send_command_object(EM::IMAP::Command.new("RUBY0001", "IDLE", ["Literal\r\nString", @bomb]))
      }.should raise_exception "bomb"
    end

    it "should not raise errors if the send_data fails" do
      @command_sender.should_receive(:send_data).and_raise(Errno::ECONNRESET)
      lambda {
        @command_sender.send_command_object(EM::IMAP::Command.new("RUBY0001", "IDLE"))
      }.should_not raise_exception
    end

    it "should fail the command if send_data fails" do
      @command_sender.should_receive(:send_data).and_raise(Errno::ECONNRESET)
      a = []
      command = EM::IMAP::Command.new("RUBY0001", "IDLE").errback{ |e| a << e }
      @command_sender.send_command_object(command)
      a.map(&:class).should == [Errno::ECONNRESET]
    end
  end

  describe EM::IMAP::CommandSender::LineBuffer do

    it "should not send anything until the buffer is full" do
      @command_sender.should_not_receive(:send_data)
      @command_sender.send_line_buffered "RUBY0001"
    end

    it "should send the entire line including CRLF" do
      @command_sender.should_receive(:send_data).with("RUBY0001 NOOP\r\n")
      @command_sender.send_line_buffered "RUBY0001"
      @command_sender.send_line_buffered " "
      @command_sender.send_line_buffered "NOOP"
      @command_sender.send_line_buffered "\r\n"
    end

    it "should send each line individually" do
      @command_sender.should_receive(:send_data).with("RUBY0001 NOOP\r\n")
      @command_sender.should_receive(:send_data).with("RUBY0002 NOOP\r\n")
      @command_sender.send_line_buffered "RUBY0001 NOOP\r\nRUBY0002 NOOP\r\n"
    end
  end

end

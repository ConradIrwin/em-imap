require 'spec_helper'

describe EM::Imap::CommandSender do

  describe "#send_authentication_data" do

    before :each do
      @command_sender = Class.new(EMStub) do 
        include EM::Imap::Connection
      end.new

      @authenticator = Class.new do
        def process; end
      end.new

      @command = EM::Imap::Command.new("AUTHENTICATE", "XDUMMY")

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

end

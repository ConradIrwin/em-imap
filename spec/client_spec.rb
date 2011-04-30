require 'spec_helper'

describe EM::Imap::Client do

  before :each do
    @connection = Class.new(EMStub) do
      include EM::Imap::Connection
    end.new
  end

  describe "connection" do
    it "should succeed if the connection receives a successful greeting" do
      a = false
      EM::Imap::Client.new(@connection).callback do |response|
        a = true
      end
      @connection.receive_data "* OK Welcome, test IMAP!\r\n"
      a.should be_true
    end

    it "should fail if the connection receives a BYE" do
      a = false
      EM::Imap::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.receive_data "* BYE Test Imap\r\n"
      a.should be_true
    end

    it "should fail if the connection receives gibberish" do
      a = false
      EM::Imap::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.receive_data "HTTP 1.1 GET /\r\n"
      a.should be_true
    end

    it "should fail if the connection does not complete" do
      a = false
      EM::Imap::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.unbind
      a.should be_true
    end
  end

  describe "commands" do
    before :each do
      @client = EM::Imap::Client.new(@connection)
      @connection.receive_data "* OK Ready to test!\r\n"
    end

    it "should execute capability and return an array" do
      a = nil
      @connection.should_receive(:send_data).with("RUBY0001 CAPABILITY\r\n")
      @client.capability.callback{ |r| a = r }
      @connection.receive_data "* CAPABILITY IMAP4REV1 XTEST IDLE\r\n"
      @connection.receive_data "RUBY0001 OK Success\r\n"
      a.should == ['IMAP4REV1', 'XTEST', 'IDLE']
    end

    it "should execute a noop" do
      a = false
      @connection.should_receive(:send_data).with("RUBY0001 NOOP\r\n")
      @client.noop.callback{ a = true }
      @connection.receive_data "RUBY0001 OK Success\r\n"
      a.should == true
    end

    describe "login" do
      it "should callback on a successful login" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0001 LOGIN conrad password\r\n")
        @client.login('conrad', 'password')
        @connection.receive_data "RUBY0001 OK conrad authenticated\r\n"
      end

      it "should errback on a failed login" do

      end
    end

    describe "logout" do
      before :each do
        @connection.should_receive(:send_data).with("RUBY0001 LOGIN conrad password\r\n")
        @client.login('conrad', 'password')
        @connection.receive_data "RUBY0001 OK conrad authenticated\r\n"
      end

      it "should succeed" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0002 LOGOUT\r\n")
        @client.logout.callback{ a = true }
        @connection.receive_data "* BYE LOGOUT Requested\r\n"
        @connection.receive_data "RUBY0002 OK Success\r\n"
        a.should == true
      end

      it "should cause any concurrently running commands to fail" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0002 LOGOUT\r\n")
        @client.logout
        @connection.should_receive(:send_data).with("RUBY0003 NOOP\r\n")
        @client.noop.errback{ a = true }
        @connection.receive_data "* BYE LOGOUT Requested\r\n"
        @connection.receive_data "RUBY0002 OK Success\r\n"
      end
    end
  end
end

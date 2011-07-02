require 'spec_helper'

describe EM::IMAP::Client do

  before :each do
    @connection = Class.new(EMStub) do
      include EM::IMAP::Connection
    end.new
  end

  describe "connection" do
    it "should succeed if the connection receives a successful greeting" do
      a = false
      EM::IMAP::Client.new(@connection).callback do |response|
        a = true
      end
      @connection.receive_data "* OK Welcome, test IMAP!\r\n"
      a.should be_true
    end

    it "should fail if the connection receives a BYE" do
      a = false
      EM::IMAP::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.receive_data "* BYE Test IMAP\r\n"
      a.should be_true
    end

    it "should fail if the connection receives gibberish" do
      a = false
      EM::IMAP::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.receive_data "HTTP 1.1 GET /\r\n"
      a.should be_true
    end

    it "should fail if the connection does not complete" do
      a = false
      EM::IMAP::Client.new(@connection).errback do |e|
        a = true
      end
      @connection.unbind
      a.should be_true
    end
  end

  describe "commands" do
    before :each do
      @client = EM::IMAP::Client.new(@connection)
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

    it "should publish the untagged responses during a select" do
      a = []
      b = nil
      @connection.should_receive(:send_data).with("RUBY0001 SELECT \"[Google Mail]/All Mail\"\r\n")
      @client.select("[Google Mail]/All Mail").listen{ |response| a << response }.callback{ b = true }.errback{ b = false }
      @connection.receive_data "* FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)\r\n" +
                               "* OK [PERMANENTFLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen \\*)]\r\n" +
                               "* OK [UIDVALIDITY 1]\r\n" +
                               "* 38871 EXISTS\r\n" + 
                               "* 0 RECENT\r\n" + 
                               "* OK [UIDNEXT 95025]\r\n" +
                               "RUBY0001 OK [READ-WRITE] [Google Mail]/All Mail selected. (Success)\r\n"

      a.map(&:name).should == ["FLAGS", "OK", "OK", "EXISTS", "RECENT", "OK", "OK"]
      a[0].data.should == [:Answered, :Flagged, :Draft, :Deleted, :Seen]
      a[1].data.code.name.should == "PERMANENTFLAGS"
      a[3].data.should == 38871
      a[4].data.should == 0
      b.should == true
    end

    it "should use utf7 for mailbox names" do
      @connection.should_receive(:send_data).with("RUBY0001 CREATE Encyclop&AOY-dia\r\n")
      @client.create("Encyclop\xc3\xa6dia")
      @connection.receive_data "* RUBY0001 OK Success\r\n"
    end

    describe "login" do
      it "should callback on a successful login" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0001 LOGIN conrad password\r\n")
        @client.login('conrad', 'password').callback{ a = true }
        @connection.receive_data "RUBY0001 OK conrad authenticated\r\n"
        a.should be_true
      end

      it "should errback on a failed login" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0001 LOGIN conrad \"pass(word)\"\r\n")
        @client.login('conrad', 'pass(word)').errback{ |response| a = response.class }
        @connection.receive_data "RUBY0001 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n"
        a.should == Net::IMAP::NoResponseError
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

  describe "multi-command concurrency" do
    before :each do
      @client = EM::IMAP::Client.new(@connection)
      @connection.receive_data "* OK Ready to test!\r\n"
    end

    it "should fail all concurrent commands if something goes wrong" do
      a = b = false
      @client.create("Encyclop\xc3\xa6dia").errback{ |e| a = true }
      @client.create("Brittanica").errback{ |e| b = true }
      @connection.should_receive(:close_connection).once
      @connection.fail_all EOFError.new("Testing error")
      a.should == true
      b.should == true
    end
  end
end

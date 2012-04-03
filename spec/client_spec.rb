require 'spec_helper'

describe EM::IMAP::Client do

  before :each do
    @connection = Class.new(EMStub) do
      include EM::IMAP::Connection
    end.new
    EM::IMAP::Connection.stub!(:connect).and_return(@connection)
  end

  describe "connection" do
    it "should succeed if the connection receives a successful greeting" do
      a = false
      EM::IMAP::Client.new("mail.example.com", 993).connect.callback do |response|
        a = true
      end
      @connection.receive_data "* OK Welcome, test IMAP!\r\n"
      a.should be_true
    end

    it "should fail if the connection receives a BYE" do
      a = false
      EM::IMAP::Client.new("mail.example.com", 993).connect.errback do |e|
        a = true
      end
      @connection.receive_data "* BYE Test IMAP\r\n"
      a.should be_true
    end

    it "should fail if the connection receives gibberish" do
      a = false
      EM::IMAP::Client.new("mail.example.com", 993).connect.errback do |e|
        a = true
      end
      @connection.receive_data "HTTP 1.1 GET /\r\n"
      a.should be_true
    end

    it "should fail if the connection does not complete" do
      a = false
      EM::IMAP::Client.new("mail.example.com", 993).connect.errback do |e|
        a = true
      end
      @connection.unbind
      a.should be_true
    end
  end

  describe "commands" do
    before :each do
      @client = EM::IMAP::Client.new("mail.example.com", 993)
      @client.connect
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

    it "should execute an IDLE correctly" do
      stopped = false
      received = nil
      @connection.should_receive(:send_data).with("RUBY0001 IDLE\r\n")
      idler = @client.idle do |response|
        received = response
      end.callback do
        stopped = true
      end
      @connection.receive_data("+ idling\r\n")
      received.should be_a Net::IMAP::ContinuationRequest

      @connection.should_receive(:send_data).with("DONE\r\n")
      idler.stop
      @connection.receive_data("RUBY0001 OK IDLE terminated (Success)\r\n")
      received.should be_a Net::IMAP::TaggedResponse
      stopped.should be_true
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

    describe "in inbox" do
      before :each do
        @connection.should_receive(:send_data).with("RUBY0001 LOGIN conrad password\r\n")
        @client.login('conrad', 'password')
        @connection.receive_data "RUBY0001 OK conrad authenticated\r\n"
        @connection.should_receive(:send_data).with("RUBY0002 SELECT Inbox\r\n")
        @client.select('Inbox')
        @connection.receive_data "RUBY0002 OK Inbox selected. (Success)\r\n"
      end

      it "should be able to run a uid_fetch" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0003 UID FETCH 631 ALL\r\n")
        @client.uid_fetch(631, 'ALL').callback{ |r| a = r }
        @connection.receive_data "* 1 FETCH (UID 631 ENVELOPE (\"Tue, 21 Feb 2012 03:48:02 +0000\" \"Wiktionary Word of the Day is down\" ((\"Robbie Pamely\" NIL \"rpamely\" \"gmail.com\")) ((\"Robbie Pamely\" NIL \"rpamely\" \"gmail.com\")) ((\"Robbie Pamely\" NIL \"rpamely\" \"gmail.com\")) ((NIL NIL \"enwikt\" \"toolserver.org\")) NIL NIL NIL \"<CAC1x9c5PL4saRbXYst7B4_dMFJ3iF6C_ux4TArWjzNkrOttBug@mail.gmail.com>\") FLAGS (\\Flagged \\Seen) INTERNALDATE \"21-Feb-2012 03:48:30 +0000\" RFC822.SIZE 5957)\r\n"
        @connection.receive_data "RUBY0003 OK Success\r\n"

        a.size.should == 1
        a.first.attr['ENVELOPE'].from.first.name.should == "Robbie Pamely"
      end

      it "should be able to run a uid_search" do
        a = nil
        @connection.should_receive(:send_data).with("RUBY0003 UID SEARCH CHARSET UTF-8 TEXT Robbie\r\n")
        @client.uid_search('CHARSET', 'UTF-8', 'TEXT', 'Robbie').callback{ |r| a = r }
        @connection.receive_data "* SEARCH 631\r\nRUBY0003 OK SEARCH completed (Success)\r\n"

        a.should == [631]
      end
    end
  end

  describe "multi-command concurrency" do
    before :each do
      @client = EM::IMAP::Client.new("mail.example.com", 993)
      @client.connect
      @connection.receive_data "* OK Ready to test!\r\n"
    end

    it "should fail all concurrent commands if something goes wrong" do
      a = b = false
      @client.create("Encyclop\xc3\xa6dia").errback{ |e| a = true }
      @client.create("Brittanica").errback{ |e| b = true }
      @connection.should_receive(:close_connection).once
      @connection.fail EOFError.new("Testing error")
      a.should == true
      b.should == true
    end

    it "should fail any commands inserted by errbacks of commands on catastrophic failure" do
      a = false
      @client.create("Encyclop\xc3\xa6dia").errback do |e|
        @client.logout.errback do
          a = true
        end
      end
      @connection.fail EOFError.new("Testing error")
      a.should == true
    end

    it "should not pass response objects to listeners added in callbacks" do
      rs = []
      @connection.should_receive(:send_data).with("RUBY0001 SELECT \"[Google Mail]/All Mail\"\r\n")
      @client.select("[Google Mail]/All Mail").callback do |response|
        @connection.should_receive(:send_data).with("RUBY0002 IDLE\r\n")
        @client.idle do |r|
          rs << r
        end
      end
      @connection.receive_data "RUBY0001 OK [READ-WRITE] [Google Mail]/All Mail selected. (Success)\r\n"
      rs.length.should == 0
      @connection.receive_data "+ idling\r\n"
      rs.length.should == 1
    end
  end
end

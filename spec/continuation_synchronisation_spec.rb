require 'spec_helper'

describe EM::Imap::ContinuationSynchronisation do
  before :each do
    @connection = Class.new(EMStub) do 
      include EM::Imap::Connection
    end.new
  end

  it "should allow things to happen when nothing is waiting" do
    a = false
    @connection.when_not_awaiting_continuation do
      a = true
    end
    a.should be_true
  end

  it "should defer blocks until the waiter is done" do
    a = false
    waiter = @connection.await_continuations{ }
    @connection.when_not_awaiting_continuation{ a = true }
    a.should be_false
    waiter.stop
    a.should be_true
  end

  it "should defer blocks multiple times if necessary" do
    a = false
    waiter1 = @connection.await_continuations{ }
    waiter2 = @connection.await_continuations{ }
    @connection.when_not_awaiting_continuation{ a = true }
    waiter1.stop
    a.should be_false
    waiter2.stop
    a.should be_true
  end

  it "should defer blocks when previously queued blocks want to synchronise" do
    a = false
    waiter1 = @connection.await_continuations{ }
    waiter2 = nil
    
    @connection.when_not_awaiting_continuation do
      waiter2 = @connection.await_continuations{ }
    end

    @connection.when_not_awaiting_continuation{ a = true }
    waiter1.stop
    a.should be_false
    waiter2.stop
    a.should be_true
  end

  it "should forward continuation responses onto those waiting for it" do
    a = nil
    waiter = @connection.await_continuations{ |response| a = response }

    response = Net::IMAP::ContinuationRequest.new("hi")
    @connection.receive_response response
    a.should == response
  end

  it "should forward many continuations if necessary" do
    a = []
    waiter = @connection.await_continuations{ |response| a << response }

    response1 = Net::IMAP::ContinuationRequest.new("hi")
    response2 = Net::IMAP::ContinuationRequest.new("hi")
    @connection.receive_response response1
    @connection.receive_response response2
    a.should == [response1, response2]
  end

  it "should not forward any continuations after the waiter has stopped waiting" do
    a = []
    waiter1 = @connection.await_continuations do |response|
      a << response
      waiter1.stop
    end
    waiter2 = @connection.await_continuations{ }

    response1 = Net::IMAP::ContinuationRequest.new("hi")
    response2 = Net::IMAP::ContinuationRequest.new("hi")
    @connection.receive_response response1
    @connection.receive_response response2
    a.should == [response1]
  end
end

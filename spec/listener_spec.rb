require 'spec_helper'

describe EM::Imap::Listener do

  it "should pass events to listeners" do
    a = []
    listener = EM::Imap::Listener.new do |event| a << event; end
    listener.receive_event 55
    a.should == [55]
  end

  it "should pass events to multiple listeners in order" do
    a = []
    listener = EM::Imap::Listener.new.listen do |event| a << [0, event]; end.
                                      listen do |event| a << [1, event]; end
    listener.receive_event 55
    a.should == [[0, 55], [1, 55]]
  end

  it "should pass multiple events to listeners" do
    a = []
    listener = EM::Imap::Listener.new do |event| a << event; end
    listener.receive_event 55
    listener.receive_event 56
    a.should == [55, 56]
  end

  it "should call the stopbacks when stopped" do
    a = []
    listener = EM::Imap::Listener.new.stopback do a << "stopped" end
    listener.stop
    a.should == ["stopped"]
  end

  it "should call the stopbacks when succeeded" do
    a = []
    listener = EM::Imap::Listener.new.stopback do a << "stopped" end
    listener.succeed
    a.should == ["stopped"]
  end

  it "should call the stopbacks when failed" do
    a = []
    listener = EM::Imap::Listener.new.stopback do a << "stopped" end
    listener.fail
    a.should == ["stopped"]
  end

  it "should not call the stopbacks when succeeded after being stopped" do
    a = []
    listener = EM::Imap::Listener.new.stopback do a << "stopped" end
    listener.stop
    listener.succeed
    a.should == ["stopped"]
  end

  it "should not call the stopbacks when failed after being stopped" do
    a = []
    listener = EM::Imap::Listener.new.stopback do a << "stopped" end
    listener.stop
    listener.fail
    a.should == ["stopped"]
  end

  it "should not receive events after having been stopped" do
    a = []
    listener = EM::Imap::Listener.new do |event| a << event end
    listener.receive_event 55
    listener.stop
    listener.receive_event 56
    a.should == [55]
  end

  it "should not call the callbacks or errbacks after being stopped" do
    a = []
    listener = EM::Imap::Listener.new.callback do a << "callback" end.
                                      errback do a << "errback" end
    listener.stop
    a.should == []
  end

  it "should permit succeed to be called form within a stopback" do
    a = []
    listener = EM::Imap::Listener.new.callback do a << "callback" end.
                                      errback do a << "errback" end.
                                      stopback do listener.succeed end
    listener.stop
    a.should == ["callback"]
  end
end

require 'spec_helper'

describe EM::IMAP::Listener do

  it "should pass events to listeners" do
    a = []
    listener = EM::IMAP::Listener.new do |event| a << event; end
    listener.receive_event 55
    a.should == [55]
  end

  it "should pass events to multiple listeners in order" do
    a = []
    listener = EM::IMAP::Listener.new.listen do |event| a << [0, event]; end.
                                      listen do |event| a << [1, event]; end
    listener.receive_event 55
    a.should == [[0, 55], [1, 55]]
  end

  it "should pass multiple events to listeners" do
    a = []
    listener = EM::IMAP::Listener.new do |event| a << event; end
    listener.receive_event 55
    listener.receive_event 56
    a.should == [55, 56]
  end

  it "should call the stopbacks when stopped" do
    a = []
    listener = EM::IMAP::Listener.new.stopback do a << "stopped" end
    listener.stop
    a.should == ["stopped"]
  end

  it "should permit succeed to be called form within a stopback" do
    a = []
    listener = EM::IMAP::Listener.new.callback do a << "callback" end.
                                      errback do a << "errback" end.
                                      stopback do listener.succeed end
    listener.stop
    a.should == ["callback"]
  end

  it "should not pass events to listeners added in listen blocks" do
    a = []
    listener = EM::IMAP::Listener.new.listen do |event|
      listener.listen do |event|
        a << event
      end
    end

    listener.receive_event 1
    listener.receive_event 2
    a.should == [2]
  end

  describe "transform" do
    before :each do
      @bottom = EM::IMAP::Listener.new
      @top = @bottom.transform{ |result| :transformed }
    end

    it "should propagate .receive_event upwards" do
      a = []
      @top.listen{ |event| a << event }
      @bottom.receive_event :event
      a.should == [:event]
    end

    it "should not propagate .receive_event downwards" do
      a = []
      @bottom.listen{ |event| a << event }
      @top.receive_event :event
      a.should == []
    end

    it "should propagate .fail upwards" do
      a = []
      @top.errback{ |error| a << error }
      @bottom.fail :fail
      a.should == [:fail]
    end

    it "should not propagate .fail downwards" do
      a = []
      @bottom.errback{ |error| a << error }
      @top.fail :fail
      a.should == []
    end

    it "should propagate .stop downwards" do
      a = []
      @bottom.stopback{ a << :stop }
      @top.stop
      a.should == [:stop]
    end

    it "should not propagate .stop upwards" do
      a = []
      @top.stopback{ a << :stop }
      @bottom.stop
      a.should == []
    end

    it "should propagate .succeed upwards through .transform" do
      a = []
      @top.callback{ |value| a << value }
      @bottom.succeed :succeeded
      a.should == [:transformed]
    end

    it "should not propagate .succeed downwards" do
      a = []
      @bottom.callback{ |value| a << value }
      @top.succeed :succeeded
      a.should == []
    end
  end
end

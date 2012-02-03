require 'spec_helper'
describe EM::IMAP::Formatter do

  before do
    @result = []
    @formatter = EM::IMAP::Formatter.new do |thing|
      if thing.is_a?(String) && @result.last.is_a?(String)
        @result[-1] += thing
      else
        @result << thing
      end
    end

    @format = lambda { |data| @result.tap{ @formatter.send_data data } }
  end

  it "should format nils" do
    @format.call(nil).should == ["NIL"]
  end

  it "should format simple strings with no quotes" do
    @format.call("FETCH").should == ["FETCH"]
  end

  it "should quote the empty string" do
    @format.call("").should == ['""']
  end

  it "should quote strings with spaces" do
    @format.call("hello world").should == ['"hello world"']
  end

  it "should make strings that contain newlines into literals" do
    @format.call("good\nmorning").should == [EM::IMAP::Formatter::Literal.new("good\nmorning")]
  end

  it "should raise an error on out-of-range ints" do
    lambda{ @format.call(2 ** 64) }.should raise_error Net::IMAP::DataFormatError
    lambda{ @format.call(-1) }.should raise_error Net::IMAP::DataFormatError
  end

  it "should be able to format in-range ints" do
    @format.call(123).should == ['123']
  end

  it "should format dates with a leading space" do
    @format.call(Time.gm(2011, 1, 1, 10, 10, 10)).should == ['" 1-Jan-2011 10:10:10 +0000"']
  end

  it "should format times in the 24 hour clock" do
    @format.call(Time.gm(2011, 10, 10, 19, 10, 10)).should == ['"10-Oct-2011 19:10:10 +0000"']
  end

  it "should format lists correctly" do
    @format.call([1,"",nil, "three"]).should == ['(1 "" NIL three)']
  end

  it "should allow for literals within lists" do
    @format.call(["oh yes", "oh\nno"]).should == ['("oh yes" ', EM::IMAP::Formatter::Literal.new("oh\nno"), ')']
  end

  it "should format symbols correctly" do
    @format.call(:hi).should == ["\\hi"]
  end

  it "should format commands correctly" do
    @format.call(EM::IMAP::Command.new('RUBY0001', 'SELECT', ['Inbox'])).should == ["RUBY0001 SELECT Inbox\r\n"]
  end

  it "should format complex commands correctly" do
    raise "yamn"
    @format.call(EM::IMAP::Command.new('RUBY1234', 'FETCH', [[Net::IMAP::MessageSet.new([1,2,3])], 'BODY'])).should == ["RUBY1234 FETCH (1,2,3) BODY\r\n"]
  end
end

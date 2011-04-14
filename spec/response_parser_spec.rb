require 'rubygems'
require 'lib/imap_connection.rb'
require 'em/connection.rb'

# FIXME: This must already exist...
class EMStub
  def initialize; post_init; end
  def post_init; end
end

describe EventMachine::ImapConnection::ResponseParser do

  before :each do 
    @response_parser = Class.new(EMStub) do 
      include EventMachine::ImapConnection::ResponseParser 
    end.new
  end

  it "should pass things through on a line-by-line basis" do
    @response_parser.should_receive(:parse).with("CAPABILITY\r\n")
    @response_parser.receive_data "CAPABILITY\r\n"
  end

  it "should split multiple lines up" do
    @response_parser.should_receive(:parse).with("CAPABILITY\r\n")
    @response_parser.should_receive(:parse).with("IDLE\r\n")
    @response_parser.receive_data "CAPABILITY\r\nIDLE\r\n"
  end

  it "should wait to join single lines" do
    @response_parser.should_receive(:parse).with("CAPABILITY\r\n")
    @response_parser.receive_data "CAPABIL"
    @response_parser.receive_data "ITY\r\n"
  end

  it "should include literals" do
    @response_parser.should_receive(:parse).with("LOGIN joe {10}\r\nblogsblogs\r\n")
    @response_parser.receive_data "LOGIN joe {10}\r\nblogsblogs\r\n"
  end

  it "should not be confused by literals that contain \r\n" do
    @response_parser.should_receive(:parse).with("LOGIN joe {4}\r\nhi\r\n\r\n")
    @response_parser.receive_data "LOGIN joe {4}\r\nhi\r\n\r\n"
  end

  it "should parse multiple literals on one line" do
    @response_parser.should_receive(:parse).with("LOGIN {3}\r\njoe{5}blogs\r\n")
    @response_parser.receive_data "LOGIN {3}\r\njoe{5}blogs\r\n"
  end

  it "should parse literals split across packets" do
    @response_parser.should_receive(:parse).with("LOGIN {3}\r\njoe{5}blogs\r\n")
    @response_parser.receive_data "LOGIN {3"
    @response_parser.receive_data "}\r\njoe{5}bl"
    @response_parser.receive_data "ogs\r\n"
  end

end

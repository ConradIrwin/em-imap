require 'spec_helper'

describe EM::IMAP::Authenticators do
  
  it "should let you add an authenticator through the EM::Imap module" do
    EM::IMAP.add_authenticator('FOO_AUTH', Object)
    Net::IMAP.send(:class_variable_get, :@@authenticators).should include 'FOO_AUTH'
  end

  it "should let you add an authenticator through an instance of client" do
    client = EM::IMAP::Client.new("mail.example.com", 993)
    client.add_authenticator('BAR_AUTH', Object)
    Net::IMAP.send(:class_variable_get, :@@authenticators).should include 'BAR_AUTH'
  end

end
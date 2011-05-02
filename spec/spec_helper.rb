# FIXME: This must already exist...
class EMStub
  def initialize; post_init; end
  def post_init; end
  def close_connection; unbind; end
end

require File.dirname( __FILE__ ) + "/../lib/em-imap"

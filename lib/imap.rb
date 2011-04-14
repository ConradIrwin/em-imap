module EventMachine
  class Imap
    def self.connect(host, port, ssl=false)
      conn = EventMachine.connect(host, port, EventMachine::ImapConnection)
      conn.start_tls if ssl
      new(conn)
    end

    def initialize(connection)
      @connection = connection
    end

    def capability
      one_data_response("CAPABILITY")
    end

    def login(username, password)
      tagged_response("LOGIN", username, password)
    end

    def logout
      tagged_response("LOGOUT")
    end

    def noop
      tagged_response("NOOP")
    end

    def select(mailbox)
      tagged_response("SELECT", mailbox)
    end


    private
    
    # The callback of a Command returns both a tagged response,
    # and optionally a list of untagged responses that were
    # generated at the same time.
    def tagged_response(*command)
      send_command(*command).transform{ |response, data| response }
    end

    def one_data_response(*command)
      send_command(*command).transform{ |response, data| data.last }
    end

    def multi_data_response(*command)
      send_command(*command).transform{ |response, data| data }
    end

    def send_command(cmd, *args)
      connection.send_command(cmd, *args)
    end

    attr_reader :connection
    private :connection
  end
end

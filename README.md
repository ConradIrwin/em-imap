An [EventMachine](http://eventmachine.org/) based [IMAP](http://tools.ietf.org/html/rfc3501) client.

## Installation

    gem install em-imap

## Usage

This document tries to introduce concepts of IMAP alongside the facilities of the library that handle them, to give you an idea of how to perform basic IMAP operations. IMAP is more fully explained in [RFC3501](http://tools.ietf.org/html/rfc3501), and the details of the library are of course in the source code.

### Connecting

Before you can communicate with an IMAP server, you must first connect to it. There are three connection parameters, the hostname, the port number, and whether to use SSL/TLS. As with every method in EM::IMAP, `EM::IMAP.connect` returns a [deferrable](http://eventmachine.rubyforge.org/docs/DEFERRABLES.html) enhanced by the [deferrable\_gratification](https://github.com/samstokes/deferrable_gratification) library.

For example, to connect to Gmail's IMAP server, you can use the following snippet:

    require 'rubygems'
    require 'em-imap'

    EM::run do
      client = EM::IMAP.connect('imap.gmail.com', 993, true)
      client.errback do |error|
        puts "Connecting failed: #{error}"
      end.callback do |hello_response|
        puts "Connecting succeeded!"
      end.bothback do
        EM::stop
      end
    end

### Authenticating

There are two authentication mechanisms in IMAP, `LOGIN` and `AUTHENTICATE`, exposed as two methods on the EM::IMAP client, `.login(username, password)` and `.authenticate(mechanism, *args)`. Again these methods both return deferrables, and the cleanest way to tie deferrables together is to use the [`.bind!`](http://samstokes.github.com/deferrable_gratification/doc/DeferrableGratification/Combinators.html#bind!-instance_method) method from deferrable\_gratification.

Extending our previous example to also log in to Gmail:

    client = EM::IMAP.connect('imap.gmail.com', 993, true)
    client.bind! do
      client.login("conrad.irwin@gmail.com", ENV["GMAIL_PASSWORD"])
    end.callback do
      puts "Connected and logged in!"
    end.errback do |error|
      puts "Connecting or logging in failed: #{error}"
    end

The `.authenticate` method is more advanced and uses the same extensible mechanism as [Net::IMAP](http://www.ruby-doc.org/stdlib/libdoc/net/imap/rdoc/classes/Net/IMAP.html). The two mechanisms supported by default are `'LOGIN'` and [`'CRAM-MD5'`](http://www.ietf.org/rfc/rfc2195.txt), other mechanisms are provided by gems like [gmail\_xoauth](https://github.com/nfo/gmail_xoauth).

### Mailbox-level IMAP

Once the authentication has completed successfully, you can perform IMAP commands that don't require a currently selected mailbox. For example to get a list of the names of all Gmail mailboxes (including labels):

    client = EM::IMAP.connect('imap.gmail.com', 993, true)
    client.bind! do
      client.login("conrad.irwin@gmail.com", ENV["GMAIL_PASSWORD"])
    end.bind! do
      client.list
    end.callback do |list|
      puts list.map(&:name)
    end.errback do |error|
      puts "Connecting, logging in or listing failed: #{error}"
    end

The useful commands available to you at this point are `.list`, `.create(mailbox)`, `.delete(mailbox)`, `.rename(old_mailbox, new_mailbox)`, `.status(mailbox)`. `.select(mailbox)` and `.examine(mailbox)` are discussed in the next section, and `.subscribe(mailbox)`, `.unsubscribe(mailbox)`, `.lsub` and `.append(mailbox, message, flags?, date_time)` are unlikely to be useful to you immediately. For a full list of IMAP commands, and detailed considerations, please refer to [RFC3501](http://tools.ietf.org/html/rfc3501).

### Message-level IMAP

In order to do useful things which actual messages, you need to first select a mailbox to interact with. There are two commands for doing this, `.select(mailbox)`, and `.examine(mailbox)`. They are the same except that `.examine` opens a mailbox in read-only mode; so that no changes are made (i.e. performing commands doesn't mark emails as read).

For example to search for all emails relevant to em-imap in Gmail:

    client = EM::IMAP.connect('imap.gmail.com', 993, true)
    client.bind! do
      client.login("conrad.irwin@gmail.com", ENV["GMAIL_PASSWORD"])
    end.bind! do
      client.select('[Google Mail]/All Mail')
    end.bind! do
      client.search('ALL', 'SUBJECT', 'em-imap')
    end.callback do |results|
      puts results
    end.errback do |error|
      puts "Something failed: #{error}"
    end

Once you have a list of message sequence numbers, as returned by search, you can actually read the emails with `.fetch`:

    client = EM::IMAP.connect('imap.gmail.com', 993, true)
    client.bind! do
      client.login("conrad.irwin@gmail.com", ENV["GMAIL_PASSWORD"])
    end.bind! do
      client.select('[Google Mail]/All Mail')
    end.bind! do
      client.search('ALL', 'SUBJECT', 'em-imap')
    end.bind! do |results|
      client.fetch(results, 'BODY[TEXT]')
    end.callback do |emails|
      puts emails.map{|email| email.attr['BODY[TEXT]'] }
    end.errback do |error|
      puts "Something failed: #{error}"
    end

The useful commands available to you at this point are `.search(*args)`, `.expunge`, `.fetch(messages, attributes)`, `.store(messages, name, values)` and `.copy(messages, mailbox)`. If you'd like to work with UIDs instead of sequence numbers, there are UID based alternatives: `.uid_search`, `.uid_fetch`, `.uid_store` and `.uid_copy`. The `.close` command and `.check` command are unlikely to be useful to you immediately.

### Untagged responses

IMAP has the notion of untagged responses (aka. unsolicited responses). The idea is that sometimes when you run a command you'd like to be updated on the state of the mailbox with which you are interacting, even though notification isn't always required. To listen for these responses, the deferrables returned by each client method have a `.listen(&block)` method. All responses received by the server, up to and including the response that completes the current command will be passed to your block.

For example, we could insert a listener into the above example to find out some interesting numbers:

    end.bind! do
      client.select('[Google Mail]/All Mail').listen do |response|
        case response.name
        when "EXISTS"
          puts "There are #{response.data} total emails in All Mail"
        when "RECENT"
          puts "There are #{response.data} new emails in All Mail"
        end
      end
    end.bind! do

One IMAP command that exists solely to receive such unsolicited responses is IDLE. The IDLE command blocks the connection so that no other commands can use it, so before you can send further commands you must `stop` the IDLE command:

    idler = client.idle

    idler.listen do |response|
      if (response.name == "EXISTS" rescue nil)
        puts "Ooh, new emails!"
        idler.stop
        idler.callback do
          # ... process new emails
        end
      end
    end.errback do |e|
      puts "Idler recieved an error: #{e}"
    end

### Concurrency

IMAP is an explicitly concurrent protocol: clients MAY send commands without waiting for the previous command to complete, and servers MAY send any untagged response at any time.

If you want to receive server responses at any time, you can call `.add_response_handler(&block)` on the client. This returns a deferrable like the IDLE command, on which you can call `stop` to stop receiving responses (which will cause the deferrable to succeed). You should also listen on the `errback` of this deferrable so that you know when the connection is closed:

    handler = client.add_response_handler do |response|
      puts "Server says: #{response}"
    end.errback do |e|
      puts "Connection closed?: #{e}"
    end
    EM::Timer.new(600){ handler.stop }

If you want to send commands without waiting for previous replies, you can also do so. em-imap handles the few cases where this is not permitted (for example, during an IDLE command) by queueing the command until the connection becomes available again. If you do this, bear in mind that any blocks that are listening on the connection may receive responses from multiple commands interleaved.

    client = EM::Imap.connect('imap.gmail.com', 993, true).callback do
      logger_in = client.login('conrad.irwin@gmail.com', ENV["GMAIL_PASSWORD"])
      selecter = client.select('[Google Mail]/All Mail')
      searcher = client.search('from:conrad@rapportive.com').callback do |results|
        puts results
      end

      logger_in.errback{ |e| selecter.fail e }
      selecter.errback{ |e| searcher.fail e }
      searcher.errback{ |e| "Something failed: #{e}" }
    end

## TODO

em-imap is still very much a work-in-progress, and the API will change as time goes by.

Before version 1, at least the following changes should be made:

1. Stop using Net::IMAP in quite so many bizarre ways, probably clearer to copy-paste the code and rename relevant classes (particular NoResponseError..)
2. Find a nicer API for some commands (maybe some objects to represent mailboxes, and/or messages?)
3. Document argument serialization.
4. Support SORT and THREAD.
5. Put the in-line documentation into a real format.

## Meta-foo

Em-imap is made available under the MIT license, see LICENSE.MIT for details

Patches and pull-requests are welcome.

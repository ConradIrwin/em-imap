Gem::Specification.new do |gem|
  gem.name = 'em-imap'
  gem.version = '0.2.2'

  gem.summary = 'An EventMachine based IMAP client.'
  gem.description = "Allows you to connect to an IMAP4rev1 server in a non-blocking fashion."

  gem.authors = ['Conrad Irwin']
  gem.email = %w(conrad@rapportive.com)
  gem.homepage = 'http://github.com/rapportive-oss/em-imap'

  gem.license = 'MIT'

  gem.required_ruby_version = '>= 1.8.7'

  gem.add_dependency 'eventmachine'
  gem.add_dependency 'deferrable_gratification'

  gem.add_development_dependency 'rspec'

  gem.files = Dir[*%w(
      lib/em-imap.rb
      lib/em-imap/*.rb
      LICENSE.MIT
      README.md
  )]
end

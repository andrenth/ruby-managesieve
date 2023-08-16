require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = 'ruby-managesieve'
  s.version = '0.4.3'
  s.summary = 'A Ruby library for the MANAGESIEVE protocol'
  s.description = <<-EOF
    ruby-managesieve is a pure-ruby implementation of the MANAGESIEVE protocol,
    allowing remote management of Sieve scripts from ruby.
  EOF
  s.requirements << 'A network connection and a MANAGESIEVE server.'
  s.files = ['lib/managesieve.rb']
  s.bindir = 'bin'
  s.executables = ['sievectl']
  s.has_rdoc = true
  s.author = 'Andre Nathan'
  s.email = 'andre@hostnet.com.br'
  s.rubyforge_project = 'ruby-managesieve'
  s.homepage = "http://managesieve.rubyforge.org"
end

if __FILE__ == $0
  Gem::Builder.new(spec).build
else
  spec
end

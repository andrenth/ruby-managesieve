require 'rubygems'

spec = Gem::Specification.new do |s|
  s.name = 'ruby-managesieve'
  s.version = '0.1.0'
  s.platform = Gem::Platform::RUBY
  
  s.summary = 'A Ruby library for the MANAGESIEVE protocol'
  s.description = <<-EOF
    ruby-managesieve is a pure-ruby implementation of the MANAGESIEVE protocol,
    allowing remote management of Sieve scripts from ruby.
  EOF
  s.requirements << 'A network connection and a MANAGESIEVE server.'
  
  s.files = Dir.glob("lib/*").delete_if {|item| item.include?("CVS")}
  
  s.require_path = 'lib'
  s.autorequire = 'managesieve'
  
  s.bindir = 'bin'
  s.executables = [ 'sievectl' ]

  s.has_rdoc = true

  s.author = 'Andre Nathan'
  s.email = 'andre@digirati.com.br'
  s.rubyforge_project = 'ruby-managesieve'
  s.homepage = "http://managesieve.rubyforge.org"
end

if __FILE__ == $0
  Gem.manage_gems
  Gem::Builder.new(spec).build
end

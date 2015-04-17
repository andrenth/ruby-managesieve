#!/usr/bin/env ruby
#
#--
# Copyright (c) 2004-2009 Andre Nathan <andre@digirati.com.br>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#++
#
# == Overview
#
# This library is a pure-ruby implementation of the MANAGESIEVE protocol, as
# specified in its
# Draft[http://managesieve.rubyforge.org/draft-martin-managesieve-04.txt].
#
# See the ManageSieve class for documentation and examples.
#
#--
# $Id: managesieve.rb,v 1.14 2009/01/13 19:22:08 andre Exp $
#++
#

require 'base64'
require 'socket'

begin
  require 'openssl'
rescue LoadError
end

#
# Define our own Base64.encode64 for compatibility with ruby <= 1.8.1, which
# defines encode64() at the top level.
#
module Base64 # :nodoc:
  def encode64(s)
    [s].pack('m')
  end
  module_function :encode64
end

class SieveAuthError < Exception; end
class SieveCommandError < Exception; end
class SieveNetworkError < Exception; end
class SieveResponseError < Exception; end

#
# ManageSieve implements MANAGESIEVE, a protocol for remote management of
# Sieve[http://www.cyrusoft.com/sieve/] scripts.
#
# The following MANAGESIEVE commands are implemented:
# * CAPABILITY
# * DELETESCRIPT
# * GETSCRIPT
# * HAVESPACE
# * LISTSCRIPTS
# * LOGOUT
# * PUTSCRIPT
# * SETACTIVE
#
# The AUTHENTICATE command is partially implemented. Currently the +LOGIN+
# and +PLAIN+ authentication mechanisms are implemented.
#
# = Example
#
#  # Create a new ManageSieve instance
#  m = ManageSieve.new(
#    :host     => 'sievehost.mydomain.com',
#    :port     => 4190,
#    :user     => 'johndoe',
#    :password => 'secret',
#    :auth     => 'PLAIN'
#  )
#
#  # List installed scripts
#  m.scripts.sort do |name, active|
#    print name
#    print active ? " (active)\n" : "\n"
#  end
#
#  script = <<__EOF__
#  require "fileinto";
#  if header :contains ["to", "cc"] "ruby-talk@ruby-lang.org" {
#    fileinto "Ruby-talk";
#  }
#  __EOF__
#
#  # Test if there's enough space for script 'foobar'
#  puts m.have_space?('foobar', script.bytesize)
#
#  # Upload it
#  m.put_script('foobar', script)
#
#  # Show its contents
#  puts m.get_script('foobar')
#
#  # Close the connection
#  m.logout
#
class ManageSieve
  SIEVE_PORT = 4190

  attr_reader :host, :port, :user, :euser, :capabilities, :login_mechs, :tls

  # Create a new ManageSieve instance. The +info+ parameter is a hash with the
  # following keys:
  #
  # [<i>:host</i>]      the sieve server
  # [<i>:port</i>]      the sieve port (defaults to 4190)
  # [<i>:user</i>]      the name of the user
  # [<i>:euser</i>]     the name of the effective user (defaults to +:user+)
  # [<i>:password</i>]  the password of the user
  # [<i>:auth_mech</i>] the authentication mechanism (defaults to +"ANONYMOUS"+)
  # [<i>:tls</i>]       use TLS (defaults to use it if the server supports it)
  #
  def initialize(info)
    @host      = info[:host]
    @port      = info[:port] || 4190
    @user      = info[:user]
    @euser     = info[:euser] || @user
    @password  = info[:password]
    @auth_mech = info[:auth] || 'ANONYMOUS'
    @tls       = info.has_key?(:tls) ? !!info[:tls] : nil

    @capabilities   = []
    @login_mechs    = []
    @implementation = ''
    @supports_tls   = false
    @socket         = TCPSocket.new(@host, @port)

    data = get_response
    server_features(data)

    if @tls and not supports_tls?
      raise SieveNetworkError, 'Server does not support TLS'
      @socket.close
    elsif @tls != false
      @tls = supports_tls?
      starttls if @tls
    end

    authenticate
    @password = nil
  end

  
  # If a block is given, calls it for each script stored on the server,
  # passing its name and status as parameters. Else, and array
  # of [ +name+, +status+ ] arrays is returned. The status is either
  # 'ACTIVE' or nil.
  def scripts
    begin
      scripts = send_command('LISTSCRIPTS')
    rescue SieveCommandError => e
      raise e, "Cannot list scripts: #{e}"
    end
    return scripts unless block_given?
    scripts.each { |name, status| yield(name, status) }
  end
  alias :each_script :scripts

  # Returns the contents of +script+ as a string.
  def get_script(script)
    begin
      data = send_command('GETSCRIPT', sieve_name(script))
    rescue SieveCommandError => e
      raise e, "Cannot get script: #{e}"
    end
    return data.join.chomp
  end

  # Uploads +script+ to the server, using +data+ as its contents.
  def put_script(script, data)
    args = sieve_name(script)
    args += ' ' + sieve_string(data) if data
    send_command('PUTSCRIPT', args)
  end

  # Deletes +script+ from the server.
  def delete_script(script)
    send_command('DELETESCRIPT', sieve_name(script))
  end

  # Sets +script+ as active.
  def set_active(script)
    send_command('SETACTIVE', sieve_name(script))
  end

  # Returns true if there is space on the server to store +script+ with
  # size +size+ and false otherwise.
  def have_space?(script, size)
    begin
      args = sieve_name(script) + ' ' + size.to_s
      send_command('HAVESPACE', args)
      return true
    rescue SieveCommandError
      return false
    end
  end

  # Returns true if the server supports TLS and false otherwise.
  def supports_tls?
    @supports_tls
  end

  # Disconnect from the server.
  def logout
    send_command('LOGOUT')
    @socket.close
  end

  private
  def authenticate # :nodoc:
    unless @login_mechs.include? @auth_mech
      raise SieveAuthError, "Server doesn't allow #{@auth_mech} authentication"
    end
    case @auth_mech
    when /PLAIN/i
      auth_plain(@euser, @user, @password)
    when /LOGIN/i
      auth_login(@user, @password)
    else
      raise SieveAuthError, "#{@auth_mech} authentication is not implemented"
    end
  end

  private
  def auth_plain(euser, user, pass) # :nodoc:
    args = [ euser, user, pass ]
    params = sieve_name('PLAIN') + ' '
    params += sieve_name(Base64.encode64(args.join(0.chr)).gsub(/\n/, ''))
    send_command('AUTHENTICATE', params)
  end

  private
  def auth_login(user, pass) # :nodoc:
    send_command('AUTHENTICATE', sieve_name('LOGIN'), false)
    send_command(sieve_name(Base64.encode64(user)).gsub(/\n/, ''), nil, false)
    send_command(sieve_name(Base64.encode64(pass)).gsub(/\n/, ''))
  end

  private
  def server_features(lines) # :nodoc:
    lines.each do |type, data|
      case type
      when 'IMPLEMENTATION'
        @implementation = data
      when 'SASL'
        @login_mechs = data.split
      when 'SIEVE'
        @capabilities = data.split
      when 'STARTTLS'
        @supports_tls = true
      end
    end
  end

  private
  def get_line # :nodoc:
    begin
      return @socket.readline.chomp
    rescue EOFError => e
      raise SieveNetworkError, "Network error: #{e}"
    end
  end

  private
  def send_command(cmd, args=nil, wait_response=true) # :nodoc:
    cmd += ' ' + args if args
    begin
      @socket.write(cmd + "\r\n")
      resp = get_response if wait_response
    rescue SieveResponseError => e
      raise SieveCommandError, "Command error: #{e}"
    end
    return resp
  end

  private
  def parse_each_line # :nodoc:
    loop do
      data = get_line

      # server ok
      m = /^OK(.*)?$/.match(data)
      yield :ok, m.captures.values_at(0, 3) and next if m

      # server error
      m = /^(NO|BYE)(.*)?$/.match(data)
      if m
        err, msg = m.captures
        size = msg.scan(/\{(\d+)\+?\}/).to_s.to_i
        yield :error, @socket.read(size.to_i + 2) and next if size > 0
        yield :error, msg and next
      end

      # quoted text
      m = /"([^"]*)"(\s"?([^"]*)"?)?$/.match(data)
      yield :quoted, m.captures.values_at(0,2) and next if m
      
      # literal
      m = /\{(\d+)\+?\}/.match(data)
      size = m.captures.first.to_i
      yield :literal, @socket.read(size + 2) and next if m  #  + 2 for \r\n
  
      # other
      yield :other, data
    end
  end

  private
  def get_response # :nodoc:
    response = []
    parse_each_line do |flag, data|
      case flag
      when :ok
        return response
      when :error
        raise SieveResponseError, data.strip.gsub(/\r\n/, ' ')
      else
        response << data
      end
    end
  end

  private
  def sieve_name(name) # :nodoc:
    return "\"#{name}\""
  end

  private
  def sieve_string(string) # :nodoc:
    return "{#{string.bytesize}+}\r\n#{string}"
  end

  private
  def starttls
    send_command('STARTTLS')
    @socket = OpenSSL::SSL::SSLSocket.new(@socket)
    @socket.sync_close = true
    @socket.connect
    data = get_response
    server_features(data)
  end
end

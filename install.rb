# $Id: install.rb,v 1.1 2004/12/20 17:49:51 andre Exp $

require 'fileutils'
require 'rbconfig'

lib = 'lib/managesieve.rb'
libdir = Config::CONFIG['sitelibdir']

begin
  puts "#{lib} -> #{libdir}"
  FileUtils::cp(lib, libdir)
rescue => e
  puts "Cannot install: #{e}"
end

# $Id: install.rb,v 1.4 2004/12/28 18:35:40 andre Exp $

require 'fileutils'
require 'rbconfig'

lib = 'lib/managesieve.rb'
bin = 'bin/sievectl'
libdir = Config::CONFIG['sitelibdir']
bindir = Config::CONFIG['bindir']

begin
  puts "#{lib} -> #{libdir}"
  FileUtils::cp(lib, libdir)
rescue => e
  puts "Cannot install #{lib}: #{e}"
end

begin
  puts "#{bin} -> #{bindir}"
  FileUtils::cp(bin, bindir)
  File::chmod(0755, "#{bindir}/sievectl")
rescue => e
  puts "Cannot install #{bin}: #{e}"
end

begin
  system("rdoc --ri-site #{lib}")
  system("rdoc --ri-site #{bin}")
rescue => e
  puts "Cannot generate RDoc: #{e}"
end

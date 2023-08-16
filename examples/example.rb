#!/usr/bin/env/ruby

require 'managesieve'

# Create a new ManageSieve instance
m = ManageSieve.new(
  :host     => 'sievehost.mydomain.com',
  :user     => 'johndoe',
  :password => 'secret',
  :auth     => 'PLAIN'
)

# List installed scripts
m.each_script do |name, active|
  print name
  print active ? " (active)\n" : "\n"
end

name = 'foo'
script = <<__EOF__
require "fileinto";
if header :contains ["to", "cc"] "ruby-talk@ruby-lang.org" {
  fileinto "Ruby-talk";
}
__EOF__

# If there's enough space for the script, upload it
# and set is as active
if m.have_space?(name, script.length)
  m.put_script(name, script)
  m.set_active(name)
end

# Show its contents
puts m.get_script(name)

# Remove it
m.delete_script(name)

# Close the connection
m.logout

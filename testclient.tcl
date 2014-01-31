#!/usr/bin/env tclsh8.6

package require mime
package require smtp

set mime_msg [mime::initialize -canonical "text/plain" -string {this is my message}]

smtp::sendmessage $mime_msg \
	-servers {localhost} -ports {8025} -header {Subject "Foo"} -header {From "foo@a.example.com"} -header {To "bar@example.com"} -queue false -usetls false

## cleanup
mime::finalize $mime_msg

puts "done."
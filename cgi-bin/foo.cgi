#!/usr/bin/env tclsh8.6

package require ncgi
package require html
interp alias {} he {} ::html::html_entities

## http://www.xdobry.de/mysqltcl/
package require mysqltcl

##

if [info exists env(SCRIPT_FILENAME)] {
	set basedir [file join [file dirname $env(SCRIPT_FILENAME)] ..]
} else {
	set basedir [file join [file dirname $::argv0] ..]
}

## cfg
source [file join $basedir etc cgi.cfg]

## db
set dbh [mysql::connect {*}$cfg(dbconnect)]

##

proc show_overview {} {
	set stmt {SELECT id, frm, rcpt, ts FROM msgs ORDER BY ts DESC LIMIT 1000}
	set result [::mysql::sel $::dbh $stmt -flatlist]

	# parray env
	puts {<table class="table">
		<tr><th>Timestamp</th><th>To</th><th>From</th></tr>
	}

	foreach {id frm rcpt ts} $result {
		set showurl "$::env(SCRIPT_NAME)?action=show&id=$id"
		puts [subst {
			<tr><td><a href="[he $showurl]">$ts</a></td>
			<td>[he $rcpt]</td>
			<td>[he $frm]</td>
			</tr>
		}]
		# puts "* $id $frm $rcpt $ts"
	}

	puts {</table>}
}

proc show_message {id} {
	if {![string is integer -strict $id] && $id > 0} {
		puts ":("
		return
	}
	set stmt "SELECT frm, rcpt, msgs.ts AS ts, valid_until, remote, data FROM msgs JOIN data ON msgs.data_id = data.id WHERE msgs.id = $id LIMIT 1"
	set result [::mysql::sel $::dbh $stmt -list]
	if {[llength $result] < 1} {
		puts "not found."
		return
	}
	lassign [lindex $result 0] frm rcpt ts valid_until remote data
	puts [subst {
		MAIL FROM: [he $frm]<br/>
		RCPT TO: [he $rcpt]<br/>
		Timestamp: [he $ts]<br/>
		Valid until: [he $valid_until]<br/>
		Received from: [he $remote]<br/>
		<pre>[he $data]</pre>
	}]
}

##

::ncgi::header {text/html; charset=utf-8} {*}{Cache-Control "no-store,no-cache,max-age=0,must-revalidate"
Expires "Thu, 01 Dec 1994 16:00:00 GMT"
Pragma "no-cache"
"X-Content-Type-Options" nosniff
"X-DNS-Prefetch-Control" off
"X-Frame-Options" sameorigin
"X-XSS-Protection" "1; mode=block"}
::ncgi::parse


## template start
puts [subst {<!DOCTYPE html>
<html>
  <head>
    <title>tmpmail.</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link href="/tmpmail/css/bootstrap.min.css" rel="stylesheet">

  </head>
  <body>
  <div class="container">
}]
# puts [subst {
#     <div class="starter-template">
#       <h1>tmpmail</h1>
#       <p class="lead">Overview</p>
#     </div>
# }]


##
# puts [ncgi::value action]
switch [ncgi::value action overview] {
	show {
		show_message [ncgi::value id 0]
	}
	overview -
	default {
		show_overview
	}
}

## template end

puts [subst {
  </div><!-- /.container -->
  

    <!-- jQuery (necessary for Bootstrap's JavaScript plugins) -->
    <script src="/tmpmail/js/jquery-2.0.3.min.js"></script>
    <!-- Include all compiled plugins (below), or include individual files as needed -->
    <script src="/tmpmail/js/bootstrap.min.js"></script>
  </body>
</html>}]


## shutdown
mysql::close $dbh
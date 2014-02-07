#!/usr/bin/env tclsh8.6

package require mysqltcl

set basedir [file join [file dirname $::argv0] ..]
source [file join $basedir etc cgi.cfg]
set dbh [mysql::connect {*}$cfg(dbconnect)]

mysql::exec $dbh {DELETE FROM msgs WHERE valid_until < CURRENT_TIMESTAMP;}
mysql::exec $dbh {DELETE FROM data WHERE NOT EXISTS (SELECT 1 FROM msgs WHERE msgs.data_id = data.id) AND ts < ADDDATE(CURRENT_TIMESTAMP, INTERVAL -1 HOUR);}

mysql::close $dbh

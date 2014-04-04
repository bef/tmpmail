tmpmail. anonymous receiving SMTP server / honeypod
===================================================

Idea
----
tmpmail is a receiving SMTP server with focus on simplicity and security for research purposes. Basically every received email is stored in a mysql database.

Features:

* accepts RFC 5321 compliant SMTP clients.
* all emails are stored in a mysql database for further processing or research.
* no MIME parser, no header parser - reduces the attack surface. If such parsers are needed in the future, they must be implemented somewhere else, e.g. in Webbrowser client-side logic.
* no authentication
* The server is implemented in fewer than 300 lines of Erlang code.
* per line timeout against denial-of-service attacks or broken TCP connections
* fancy CGI-based reader

Installation / Running
----------------------

* Install erlang
* Clone the git repository:

		# cd /opt
		# git clone https://github.com/bef/tmpmail.git

* Clone mysql library

		# cd /opt/tmpmail
		# git clone https://github.com/Eonblast/Emysql

* Copy/edit etc/foo.cfg and etc/cgi.cfg.
* Create a dedicated mysql database:

		mysql> CREATE DATABASE tmpmail;
		mysql> CREATE USER 'tmpmail'@'localhost' IDENTIFIED BY 'some_pass';
		mysql> GRANT ALL PRIVILEGES ON tmpmail.* TO 'tmpmail'@'localhost';
		mysql> FLUSH PRIVILEGES;

* Run - it's probably best to use a screen or tmux terminal multiplexer. There is no daemon mode.

		user$ ./foo.erl

* tmpmail should listen on an unprivileged port >1024. Connections to port 25 can be redirected, e.g.

		# iptables -t nat -A PREROUTING -d 10.0.0.1 -p tcp --dport 25 -j DNAT --to-destination 127.0.0.1:8025


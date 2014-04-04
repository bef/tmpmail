#!/usr/bin/env escript
%%! -smp enable
%%
%% -- anonymous receiving-only tmp-mail server --
%% [ quick and dirty version ]
%% (c) BeF - 2014-02-04
%% all rights reserved. do not distribute.
%%

-mode(compile).
-include("include/foo.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% --- TCP SERVER ---

start_tcp(Port, NumProcs) ->
	case gen_tcp:listen(Port, [list, inet, {active, false}, {packet, line}]) of
		{ok, LS} ->
			start_tcp_servers(NumProcs, LS),
			LS;
		{error, eaddrinuse=Reason} ->
			io:format("~w; retry in a few seconds~n", [Reason]),
			timer:sleep(2000),
			start_tcp(Port, NumProcs);
		{error, Reason} ->
			io:format("ERROR: ~p~n", [Reason]),
			halt(1)
	end.

start_tcp_servers(0, _) -> ok;
start_tcp_servers(N, LS) ->
	spawn(fun() -> tcp_server(LS) end),
	start_tcp_servers(N-1, LS).

tcp_server(LS) ->
	io:format("~p: new tcp server on socket ~p~n", [self(), LS]),
	case gen_tcp:accept(LS) of
		{ok, S} ->
			PeerStr = case inet:peername(S) of
				{ok, {PeerAddr, _PeerPort}} -> string:join([integer_to_list(X) || X <- tuple_to_list(PeerAddr)],".");
				_ -> "?"
			end,
			io:format("~p/~p: new connection from ~p~n", [self(), S, PeerStr]),
			
			smtp_reply(S, "220", "Service Ready"),
			%% 554 service not ready.
			
			tcp_loop(S, #session{remote=PeerStr}),
			tcp_server(LS);
		Other ->
			io:format("~p: accept is gone: ~p~n", [self(), Other]),
			ok 
	end.


% tcp_loop(S) ->
	% tcp_loop(S, #session{}).

tcp_loop(S, State) ->
	
	inet:setopts(S,[{active,once}]),
	receive
		{tcp, S, Data} ->
			io:format("~p/~p: data: ~p~n", [self(), S, Data]),
			State2 = handle_smtp(S, State, Data),
			tcp_loop(S, State2);
		{tcp_closed, S} ->
			io:format("~p/~p: socket closed~n", [self(), S]),
			ok
	after 60000 -> %% 1min line timeout - not RFC compliant, but close enough
		io:format("~p/~p: timeout~n", [self(), S]),
		gen_tcp:shutdown(S, read_write),
		tcp_loop(S, State)
	end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% -- miminal SMTP server implementation --
%% see https://tools.ietf.org/html/rfc5321

smtp_reply(S, Code, Line) ->
	smtp_reply_multiline(S, Code, [Line]).

smtp_reply_multiline(S, Code, Lines) when is_integer(Code) ->
	smtp_reply_multiline(S, integer_to_list(Code), Lines);
smtp_reply_multiline(S, Code, [Line]) ->
	gen_tcp:send(S, Code ++ " " ++ Line ++ "\r\n");
smtp_reply_multiline(S, Code, [Line|Lines]) ->
	gen_tcp:send(S, Code ++ "-" ++ Line ++ "\r\n"),
	smtp_reply_multiline(S, Code, Lines).

	
handle_smtp(S, #session{mode=cmd}=State, Data) ->
	First = string:to_upper(string:substr(Data, 1, 4)),
	handle_cmd(S, State, First, Data);
handle_smtp(S, #session{mode=data}=State, Data) ->
	handle_data(S, State, Data).


reset_session(State) ->
	State#session{from="", to=[], data=""}.

helo_reply_250(S, "HELO") ->
	smtp_reply(S, "250", "localhost");
helo_reply_250(S, "EHLO") ->
	smtp_reply_multiline(S, "250", ["localhost - nice to meet you.", "NOOP", "HELP"]).

handle_helo(S, State, First, Data) ->
	case re:run(Data, "^" ++ First ++ "\\s*(.*?)[\r\n]", [{capture, [1], list}, unicode, caseless]) of
		nomatch ->
			smtp_reply(S, "501", ":( bad " ++ First),
			State;
		{match, [Helo]} ->
			helo_reply_250(S, First),
			State2 = reset_session(State),
			State2#session{helo=Helo}
	end.

handle_cmd(S, State, "HELO"=First, Data) ->
	handle_helo(S, State, First, Data);

handle_cmd(S, State, "EHLO"=First, Data) ->
	handle_helo(S, State, First, Data);


handle_cmd(S, State, "MAIL", _Data) when State#session.helo =:= "" ->
	smtp_reply(S, "503", "hello?"),
	State;

handle_cmd(S, State, "MAIL", Data) ->
	%% error code 555
	%% tmp error 455
	%% transaction beginning not acceptable 501
	case re:run(Data, "^MAIL FROM:\\s*<" ++ ?RE_EMAIL_ADDR ++ ">", [{capture, [1], list}, unicode, caseless]) of
		nomatch ->
			smtp_reply(S, "501", "Not acceptable"),
			State;
		{match, [Addr]} ->
			smtp_reply(S, "250", "OK"),
			State#session{from=Addr, to=[]}
	end;

handle_cmd(S, State, "RCPT", _Data) when State#session.from =:= "" ->
	smtp_reply(S, "503", "Transaction not started. Please try again."),
	State;
handle_cmd(S, State, "RCPT", _Data) when length(State#session.to) >= 10 ->
	smtp_reply(S, "452", "Too many recipients"),
	State;
handle_cmd(S, State, "RCPT", Data) ->
	%% relay error (, in address) 550
	%% 503 Bad sequence of commands
    %% 452 Too many recipients
	case re:run(Data, "^RCPT TO:\\s*<" ++ ?RE_EMAIL_ADDR ++ ">", [{capture, [1], list}, unicode, caseless]) of
		nomatch ->
			smtp_reply(S, "501", "Not acceptable"),
			State;
		{match, [Addr]} ->
			smtp_reply(S, "250", "OK"),
			State#session{to=[Addr|State#session.to]}
	end;

handle_cmd(S, State, "DATA", _Data) when State#session.from =/= "", State#session.to =/= [] ->
	smtp_reply(S, "354", "go ahead."),
	State#session{mode=data};
handle_cmd(S, State, "DATA", _Data) ->
	smtp_reply(S, "503", "Bad sequence. Please try again."),
	State;

handle_cmd(S, State, "VRFY", _Data) ->
	smtp_reply(S, "502", "Command not implemented"),
	State;

handle_cmd(S, State, "EXPN", _Data) ->
	smtp_reply(S, "502", "Command not implemented"),
	State;

handle_cmd(S, State, "RSET", _Data) ->
	smtp_reply(S, "250", "OK"),
	reset_session(State);

handle_cmd(S, State, "NOOP", _Data) ->
	smtp_reply(S, "250", "OK. did nothing."),
	State;

handle_cmd(S, State, "HELP", _Data) ->
	smtp_reply(S, "511", "I need somebody. HELP. I need anybody. hmm. mm."),
	%% 214: help message fore one specific command
	State;

handle_cmd(S, _State, "QUIT", _Data) ->
	smtp_reply(S, "221", "Bye."),
	gen_tcp:shutdown(S, read_write),
	#session{};

handle_cmd(S, State, _First, _Data) ->
	smtp_reply(S, "500", "Command not recognized"),
	State.


handle_data(S, State, ".\r\n") ->
	handle_end_of_data(S, State);
handle_data(S, State, ".\n") ->
	handle_end_of_data(S, State);
handle_data(S, State, _Data) when length(State#session.data) > 1024*1024*2 ->
	smtp_reply(S, "552", "Too much mail data."),
	State#session{data=""};
handle_data(_S, State, Data) ->
	OldData = State#session.data,
	State#session{data=OldData++Data}. %% rather inefficient, but ok for the moment.
	%% 552 Too much mail data.

handle_end_of_data(S, State) ->
	smtp_reply(S, "250", "OK"),
	% io:format("~p~n", [State#session.data]),
	
	try store_data(State) of
		ok ->
			smtp_reply(S, "250", "OK")
	catch
		exit:X ->
			io:format("ERR: ~p~n", [X]),
			smtp_reply(S, "451", "Requested action aborted: temporary error in processing")
	end,
	
	State#session{mode=cmd, data="", from="", to=[]}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% --- mysql storage ---
%% using https://github.com/Eonblast/Emysql

init_storage({mysql, {User, Pass, Host, Port, Db}}) ->
	crypto:start(),
	application:start(emysql),
	
	crypto:start(),
	application:start(emysql),
	
	ok = emysql:add_pool(tm_pool, 1, User, Pass, Host, Port, Db, utf8),

	emysql:prepare(insmsg_stmt, <<"INSERT INTO msgs (helo, frm, rcpt, data_id, valid_until, remote) VALUES (?, ?, ?, ?, ADDDATE(CURRENT_TIMESTAMP, INTERVAL 7 DAY), ?)">>),
	emysql:prepare(insdata_stmt, <<"INSERT INTO data (data) VALUES (?)">>),

	ok.

shutdown_storage() ->
	ok.


store_data(State) ->
	Result = emysql:execute(tm_pool, insdata_stmt, [State#session.data]),
	LastID = emysql_util:insert_id(Result),
	store_msg(State, State#session.to, LastID).

store_msg(_, [], _) -> ok;
store_msg(State, [Rcpt|Rcpts], LastID) ->
	emysql:execute(tm_pool, insmsg_stmt, [State#session.helo, State#session.from, Rcpt, LastID, State#session.remote]),
	store_msg(State, Rcpts, LastID).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

main(_) ->
	io:format("~s~n", ["tmpmail. anonymous smtp server. author: bef@sektioneins.de"]),
	
	%% log errors to console
	error_logger:tty(true),
	
	SN = escript:script_name(),
	BaseDir = filename:dirname(SN),
	code:add_patha(filename:join([BaseDir, "Emysql", "ebin"])),
	
	{ok, Config} = file:script(filename:join([BaseDir, "etc", "foo.cfg"])),
	
	%% storage-start
	init_storage(lists:keyfind(mysql, 1, Config)),
	
	%% start SMTP server
	{tcpserver, {Port, NumProcs}} = lists:keyfind(tcpserver, 1, Config),
	LS = start_tcp(Port, NumProcs),
	
	%% wait...
	io:get_line("[*]"), %% hier könnte man noch ein kleines CLI bauen.
	
	%% shutdown
	io:format("shutdown.~n"),
	gen_tcp:close(LS),
	shutdown_storage(),
	
	ok.
	% receive foo -> bar end.

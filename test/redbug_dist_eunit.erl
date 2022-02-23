%% -*- mode: erlang; erlang-indent-level: 4 -*-
-module(redbug_dist_eunit).

-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").

x_test_() ->
    [?_assertMatch(
        {noconnection,
         [{call, {{erlang, nodes, []}, <<>>}, _, _}|_]},
        runner(
          mk_tracer("erlang:nodes/0", [{time, 3000}]),
          mk_action(100, 100, "erlang:nodes(). "))),

     ?_assertMatch(
        {timeout,
         [{call, {{erlang, nodes, []}, <<>>}, _, _}|_]},
        runner(
          mk_tracer("erlang:nodes/0", [{time, 300}]),
          mk_action(100, 100, "erlang:nodes(). "))),

     ?_assertMatch(
        {timeout,
         [{call,{{file,read_file_info,["/"]},<<>>},_,_},
          {retn,{{file,read_file_info,1},{ok,#{'_RECORD':=file_info}}},_,_},
          {call,{{erlang,setelement,[1,{ok,#{'_RECORD':=file_info}},bla]},<<>>},_,_}]},
        runner(
          mk_tracer(
            ["erlang:setelement(_, {_, file#file_info{type=directory}}, _)",
             "file:read_file_info->return"],
            [{time, 300}, {records, [file]}]),
          mk_action(100, 100, "setelement(1, file:read_file_info(\"/\"), bla). "))),

     ?_assertMatch(
        {timeout,
         [{call,{{file,read_file_info,["/"]},<<>>},_,_},
          {retn,{{file,read_file_info,1},{ok,#{'_RECORD':=file_info}}},_,_}]},
        runner(
          mk_tracer(
            ["erlang:setelement(_, {_, file#file_info{type=regular}}, _)",
             "file:read_file_info->return"],
            [{time, 300}, {records, file}]),
          mk_action(100, 100, "setelement(1, file:read_file_info(\"/\"), bla). "))),

     ?_assertMatch(
        {timeout,
         [{call,{{file,read_file_info,["/"]},<<>>},_,_},
          {retn,{{file,read_file_info,1},{ok,#file_info{}}},_,_},
          {call,{{erlang,setelement,[1,{ok,#file_info{}},bla]},<<>>},_,_}]},
        runner(
          mk_tracer(
            ["erlang:setelement(_, {_, file#file_info{type=directory}}, _)",
             "file:read_file_info->return"],
            [{time, 300}]),
          mk_action(100, 100, "setelement(1, file:read_file_info(\"/\"), bla). ")))].

mk_tracer(RTP, Opts) ->
    fun(Peer) ->
        Res = redbug:start(RTP, [{target, Peer}, blocking]++Opts),
        receive {pid, P} -> P ! {res, Res} end
    end.

mk_action(PreTO, PostTO, Str) ->
    {done, {ok, Ts, 0}, []} = erl_scan:tokens([], Str, 0),
    {ok, Es} = erl_parse:parse_exprs(Ts),
    Bs = erl_eval:new_bindings(),
    fun(Peer) ->
        timer:sleep(PreTO),
        rpc:call(Peer, erl_eval, exprs, [Es, Bs]),
        timer:sleep(PostTO)
    end.

runner(Tracer, Action) ->
    os:cmd("epmd -daemon"),
    [net_kernel:start([eunit_master, shortnames]) || node() =:= nonode@nohost],
    PeerName = eunit_inferior,
    {ok, Peer, NodeName} = start_peer(PeerName),
    {Pid, _} = spawn_monitor(fun() -> Tracer(NodeName) end),
    Action(NodeName),
    stop_peer(Peer, NodeName),
    Pid ! {pid, self()},
    receive {res, X} -> X after 1000 -> timeout end.
    

-ifdef(use_peer).

stop_peer(Peer, _PeerName) ->
    ok = peer:stop(Peer).

start_peer(PeerName) ->
    Opts = #{name => PeerName, wait_boot => 5000},
    peer:start_link(Opts).

-elif(OTP_RELEASE).

stop_peer(Slave, _) ->
    {ok, Slave} = ct_slave:stop(Slave).

start_peer(SlaveName)
    Opts = [{kill_if_fail, true}, {monitor_master, true}, {boot_timeout, 5}],
    {ok, NodeName} = ct_slave:start(SlaveName, Opts),
    {ok, NodeName, NodeName}.

-else.

stop_peer(Slave, SlaveName) ->
    {ok, Slave} = ct_slave:stop(SlaveName).

start_peer(SlaveName) ->
    Opts = [{kill_if_fail, true}, {monitor_master, true}, {boot_timeout, 5}],
    {ok, NodeName} = ct_slave:start(SlaveName, Opts),
    {ok, NodeName, NodeName}.

-endif.

%% mk_interpreted_fun(Str) ->
%%     {ok, Ts, _} = erl_scan:string(Str),
%%     {ok, [AST]} = erl_parse:parse_exprs(Ts),
%%     {value, Fun, []} = erl_eval:expr(AST, []),
%%     Fun.

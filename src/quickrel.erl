-module(quickrel).
-export([quickrel/2]).
-include_lib("kernel/include/file.hrl").

quickrel(_Config, ReltoolFile) ->
 R = file:consult(ReltoolFile),
 case R of
	 {ok, [{application, _, _}]} ->
    ok;
	 {ok, Terms} ->
    {ok, Cwd} = file:get_cwd(),
    Dir = proplists:get_value(target_dir, Terms, Cwd),
    build(ReltoolFile, Dir);
	 _ ->
		 ok
 end.

%% internal

build(Reltool, Path0) ->
   Path = filename:absname(Path0),
   {ok, ReltoolConfig0} = file:consult(Reltool),
   {sys, RelProps} = ReltoolConfig = {sys, proplists:get_value(sys, ReltoolConfig0)},
   LibDirs = proplists:get_value(lib_dirs, RelProps, []),
   code:add_pathsa(lists:concat([ filelib:wildcard(filename:join([LibDir, "*", "ebin"])) || LibDir <- LibDirs ])),
   BootRel = proplists:get_value(boot_rel, RelProps),
   {ok, Cwd} = file:get_cwd(),
   file:set_cwd(filename:dirname(Reltool)),
   %%
   filelib:ensure_dir(filename:join([Path, "lib"]) ++ "/"),
   {ok, RelSrv} = reltool:start_server([{config, ReltoolConfig}]),
   rebar_log:log(info, "Generating release...~n", []),
   {ok, Rel} = reltool:get_rel(RelSrv, BootRel),
   rebar_log:log(info, "Generating boot script...~n", []),
   {ok, Script} = reltool:get_script(RelSrv, BootRel),
   
   {release, {BootRel, _RelVer}, _Erts, Deps} = Rel,
   file:set_cwd(Cwd),

   rebar_log:log(info, "Linking libraries...~n", []),
   [ process_dep(filename:join([Path, "lib"]), Dep) || Dep <- Deps ],

   rebar_log:log(info, "Serializing boot & start scripts...~n", []),

   ScriptFile = filename:join([Path, BootRel ++ ".script"]),
   file:write_file(ScriptFile, io_lib:format("~p.~n",[Script])),
   systools:script2boot(filename:join([filename:dirname(ScriptFile),
         filename:basename(ScriptFile, ".script")])),

   {ok, [[RootDir]]} = init:get_argument(root),
   ErtsVersion = erlang:system_info(version),
   file:write_file(filename:join([Path, "start"]),
                   io_lib:format(
                   "#! /bin/sh\n"
                   "ERTS_DIR=~s\n"
                   "ROOTDIR=$(cd ${0%/*} && pwd)\n"
                   "EMU=beam\n"
                   "BINDIR=$ERTS_DIR/bin\n"
                   "cd $ROOTDIR\n"
                   "export ROOTDIR EMU BINDIR\n"
                   "exec $BINDIR/erlexec -boot ~s $@\n",
                   [filename:join([RootDir, "erts-" ++ ErtsVersion]), 
                    filename:join([Path, BootRel])])),
   {ok, FI} = file:read_file_info(filename:join([Path, "start"])),
   file:write_file_info(filename:join([Path, "start"]), FI#file_info{ mode = FI#file_info.mode bor 8#00110 }),  
 
   %% 
   ok.

 process_dep(Path, {Name, Version}) ->
   LibDir = code:lib_dir(Name),
   case file:make_symlink(filename:absname(LibDir), filename:join([Path, atom_to_list(Name) ++ "-" ++ Version])) of
		 ok -> ok;
		 {error, eexist} -> ok
	 end;
 process_dep(Path, {Name, Version, _}) ->
   process_dep(Path, {Name, Version});
 process_dep(Path, {Name, Version, _, _}) ->
	 process_dep(Path, {Name, Version}).

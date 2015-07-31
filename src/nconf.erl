%%%=============================================================================
%%% @copyright (C) 2015, Erlang Solutions Ltd
%%% @doc Module for reading the contents of an nconf config file and modifying
%%% the configuration parameters accordingly.
%%%
%%% The following commands are available in an nconf config file:
%%%
%%% ```
%%%    {set, AppName, ParamName, Path1, ..., PathN, Replacement}
%%%    {replace, AppName, ParamName, Path1, ..., PathN, Replacement}
%%%    {unset, AppName, ParamName, Path1, ..., PathN}
%%% '''
%%% @end
%%%=============================================================================
-module(nconf).
-copyright("2015, Erlang Solutions Ltd.").

%% API
-export([apply_config/1]).

%% Types
-export_type([config_tuples/0]).

%% Exports for unit test
-ifdef(TEST).
%% Cover ignores the `export_all' option prior to R16B03, so export
%% functions used in EUnit tests directly here
-export([read_config/1,
         apply_config_tuples/1]).
-endif.

%%------------------------------------------------------------------------------
%% Types
%%------------------------------------------------------------------------------

-type config_tuples() :: [tuple()].
%% A list of tuples, representing the contents of an nconf config file.

%%%=============================================================================
%%% External functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Modify the configuration parameters according to an nconf config file.
%% @end
%%------------------------------------------------------------------------------
-spec apply_config(FileName :: file:name_all()) -> any().
apply_config(FileName) ->
    case read_config(FileName) of
        {ok, ConfigTuples} ->
            case apply_config_tuples(ConfigTuples) of
                ok ->
                    ok;
                {error, Errors} ->
                    ApplyErrorMsg = "Error when applying ~s: ~p",
                    [ error_logger:error_msg(ApplyErrorMsg, [FileName, Error])
                    || Error <- Errors
                    ]
            end;
        {error, {_, ReasonStr}} ->
            ReadErrorMsg = "Error when reading ~s: ~s",
            error_logger:error_msg(ReadErrorMsg, [FileName, ReasonStr])
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Read an nconf config file.
%% @end
%%------------------------------------------------------------------------------
-spec read_config(FileName :: file:name_all()) ->
          {ok, config_tuples()} |
          {error, {Reason :: term(), ReasonStr :: string()}}.
read_config(FileName) ->
    case file:consult(FileName) of
        {ok, Terms} ->
            {ok, Terms};
        {error, Reason} ->
            ErrorStr = file:format_error(Reason),
            {error, {Reason, ErrorStr}}
    end.

%%------------------------------------------------------------------------------
%% @doc Modify the configuration parameters according to the configuration
%% tuples.
%% @end
%%------------------------------------------------------------------------------
-spec apply_config_tuples(Config :: config_tuples()) ->
          ok |
          {error, ErrorList :: [term()]}. % todo
apply_config_tuples(Config) ->
    ErrorFun =
        fun
            (ConfigTuple) when is_tuple(ConfigTuple) ->
                case apply_config_tuple(tuple_to_list(ConfigTuple)) of
                    ok ->
                        %% Don't add anything to the error list.
                        false;
                    {error, Reason} ->
                        %% Add the error to the error list.
                        {true, {Reason, ConfigTuple}}
                end;
            (Term) ->
                  %% Add the error to the error list.
                  {true, {not_a_tuple, Term}}
        end,
    ErrorList = lists:filtermap(ErrorFun, Config),
    case ErrorList of
        [] ->
            ok;
        _ ->
            {error, ErrorList}
    end.

%%------------------------------------------------------------------------------
%% @doc Modify the configuration parameters according to the configuration
%% tuple.
%%
%% This function receives the tuple in a list so that it can do pattern matching
%% on it.
%%
%% ConfigTuple formats:
%%
%% ```
%%    {set, AppName, ParamName, Path1, ..., PathN, Replacement}
%%    {replace, AppName, ParamName, Path1, ..., PathN, Replacement}
%%    {unset, AppName, ParamName, Path1, ..., PathN}
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec apply_config_tuple(ConfigTuple :: [term()]) -> ok |
                                                     {error, Reason :: term()}.
apply_config_tuple([set, AppName, ParamName | Rest = [_|_]]) ->
    Path = droplast(Rest),
    Replacement = {set, lists:last(Rest)},
    case apply_config_change(AppName, ParamName, Path, Replacement) of
        ok ->
            ok;
        {error, _} = Error ->
            Error
    end;
apply_config_tuple([replace, AppName, ParamName | Rest = [_, _|_]]) ->
    %% A 'replace' command needs to have at least one Path component, since the
    %% AppName/ParamName itself cannot be replaced with a custom term.
    Path = droplast(Rest),
    Replacement = {replace, lists:last(Rest)},
    case apply_config_change(AppName, ParamName, Path, Replacement) of
        ok ->
            ok;
        {error, _} = Error ->
            Error
    end;
apply_config_tuple([unset, AppName, ParamName | Path]) ->
    case apply_config_change(AppName, ParamName, Path, unset) of
        ok ->
            ok;
        {error, _} = Error ->
            Error
    end;
apply_config_tuple([Cmd|_]) when Cmd =:= set;
                                 Cmd =:= unset;
                                 Cmd =:= replace ->
    {error, tuple_too_short};
apply_config_tuple([Cmd|_]) ->
    {error, {unknown_command, Cmd}}.

%%------------------------------------------------------------------------------
%% @doc Change the value of the configuration entry
%% AppName/ParamName/Path1/.../PathN to `Replacement'.
%% @end
%%------------------------------------------------------------------------------
-spec apply_config_change(AppName :: atom(),
                          ParamName :: atom(),
                          Path :: [term()],
                          Replacement :: {set, term()} |
                                         {replace, term()} |
                                          unset) ->
        ok |
        {error, Reason :: term()}.
apply_config_change(AppName, ParamName, [], unset) ->
    %% Unset the whole config entry, e.g.:
    %%
    %%     {unset, snmp, agent}.
    application:unset_env(AppName, ParamName);
apply_config_change(AppName, ParamName, Path, Replacement) ->
    OldValue =
        case application:get_env(AppName, ParamName) of
            undefined ->
                %% We assume that this parameter is a proplist so that
                %% replace/3 can dig into it. If it is fully replaced, that's
                %% fine too.
                [];
            {ok, Val} ->
                Val
        end,
    case replace(OldValue, Path, Replacement) of
        {ok, NewValue} ->
            application:set_env(AppName, ParamName, NewValue),
            ok;
        {error, _} = Error ->
            Error
    end.

%%------------------------------------------------------------------------------
%% @doc Replace the term inside `OldValue' that can be accessed through the
%% given path with `Replacement'.
%%
%% Examples:
%%
%% ```
%% - replace(old, [], new) -> new
%% - replace([{a, [{b, 1}, {c, 2}]}, {d, 3}], [a, b], 0) ->
%%           [{a, [{b, 0}, {c, 2}]}, {d, 3}]
%% '''
%% @end
%%------------------------------------------------------------------------------
-spec replace(OldValue :: term(),
              Path :: [term()],
              Replacement :: {set, term()} |
                             {replace, term()} |
                             unset) ->
          {ok, NewValue :: term()} |
          {error, {tuple_list_expected, Keys :: [term()], OldValue2 :: term()}}.

replace(_OldValue, [] = _Path, {set, ReplacementTerm}) ->
    %% We need to simply replace the old value with the replacement.
    %% Example:
    %% - OldValue = 1
    %% - Path = []
    %% - ReplacementTerm = 2
    %% --> Result = 2

    {ok, ReplacementTerm};

replace(OldTupleList, [Key] = _Path, {replace, ReplacementTuple})
  when is_list(OldTupleList) ->
    %% Key is present in the OldTupleList, and there is no more element
    %% in the Path, so we should replace the key in OldTupleList.
    %% Example:
    %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
    %% - Path = [a]
    %% - Replacement = {a, 1, []}
    %% --> Result = [{a, 1, []}, {b, 2}]

    {ok, [ReplacementTuple|lists:keydelete(Key, 1, OldTupleList)]};

replace(OldTupleList, [Key] = _Path, unset) when is_list(OldTupleList) ->
    %% Key is present in the OldTupleList, and there is no more element
    %% in the Path, so we should remove the key from OldTupleList.
    %% Example 1:
    %% - OldTupleList = [{a, "", 1}, {b, 2}]
    %% - Path = [a]
    %% --> Result = [{b, 2}]

    {ok, lists:keydelete(Key, 1, OldTupleList)};

replace(OldTupleList, [Key|PathRest] = Path, Replacement)
  when is_list(OldTupleList) ->
    case {Replacement, lists:keyfind(Key, 1, OldTupleList)} of
        {unset, false} ->
            %% Key is not present and we want to delete it, so there is nothing
            %% to be done.
            %% Example:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [c, x]
            %% --> Result = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            {ok, OldTupleList};
        {{set, ReplacementTerm}, false} ->
            %% Key is not present in the OldTupleList, so it should be added.
            %% Example 1:
            %% - OldTupleList = [{a, 1}, {b, 2}]
            %% - Path = [c]
            %% - ReplacementTerm: 33
            %% --> Result = [{c, 33}, {a, 1}, {b, 2}]
            %% Example 2:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [c, x]
            %% - ReplacementTerm = 33
            %% --> Result = [{c, [{x, 33}]}, {a, [{x, 1}, {y, 2}]}, {b, 2}]
            %%
            %% Coming into this branch might be the result of a typo in
            %% the config, so let's log it.
            InfoMsg =
                "Configuring non-configured path: ~p "
                "(OldTupleList=~p, ReplacementTerm=~p)",
            error_logger:info_msg(InfoMsg, [Path, OldTupleList, ReplacementTerm]),

            NewElement =
                lists:foldl(
                    %% Example 2 execution:
                    %% 1. Key = x, Acc = 33 --> [{x, 33}]
                    %% 2. Key = c, Acc = [{x, 33}] --> [{c, [{x, 33}]}]
                    fun(Key0, Acc) ->
                        [{Key0, Acc}]
                    end, ReplacementTerm, lists:reverse(Path)),
            {ok, NewElement ++ OldTupleList};

        {{replace, ReplacementTuple}, false} ->
            %% Key is not present in the OldTupleList, so it should be added.

            %% Example 1:
            %% - OldTupleList = [{a, 1}, {b, 2}]
            %% - Path = [c]
            %% - ReplacementTuple: {c, 1, 2}
            %% --> Result = [{c, 1, 2}, {a, 1}, {b, 2}]
            %%
            %% Example 2:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [c, x]
            %% - ReplacementTuple = {x, 1, 2}
            %% --> Result = [{c, [{x, 1, 2}]}, {a, [{x, 1}, {y, 2}]}, {b, 2}]

            %% Coming into this branch might be the result of a typo in
            %% the config, so let's log it.
            InfoMsg =
                "Configuring non-configured path: ~p "
                "(OldTupleList=~p, ReplacementTuple=~p)",
            error_logger:info_msg(InfoMsg, [Path, OldTupleList, ReplacementTuple]),

            Path2 = droplast(Path),
            NewElement =
                lists:foldl(
                    %% Example 2 execution:
                    %% 1. Key = c, Acc = {x, 1, 2} --> {c, [{x, 1, 2}]}
                    fun(Key0, Acc) ->
                        {Key0, [Acc]}
                    end, ReplacementTuple, lists:reverse(Path2)),
            {ok, [NewElement|OldTupleList]};

        {_Replacement, OldTuple} ->
            %% Key is present in the OldTupleList, so we should continue
            %% following the Path.
            %% Example 1:
            %% - OldTupleList = [{a, "", 1}, {b, 2}]
            %% - Path = [a]
            %% - Replacement = {set, 11}
            %% - OldTuple = {a, "", 1}
            %% --> Result = [{a, "", 11}, {b, 2}]
            %% Example 2:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [a, x]
            %% - Replacement = {set, 11}
            %% - OldTuple = {a, [{x, 1}, {y, 2}]}
            %% --> Result = [{a, [{x, 11}, {y, 2}]}, {b, 2}]
            %% Example 3:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [a, x]
            %% - Replacement = unset
            %% - OldTuple = {a, [{x, 1}, {y, 2}]}
            %% --> Result = [{a, [{y, 2}]}, {b, 2}]
            %% Example 4:
            %% - OldTupleList = [{a, [{x, 1}, {y, 2}]}, {b, 2}]
            %% - Path = [a, x]
            %% - Replacement = {replace, {x, 1, 2}}
            %% - OldTuple = {a, [{x, 1}, {y, 2}]}
            %% --> Result = [{a, [{x, 1, 2}]}, {b, 2}]
            %%
            %% We don't assume that the tuple is a pair, because we might have
            %% let's say tuples of 4:
            %%
            %%     {main_key,
            %%      [one],
            %%      [two],
            %%      [{key, value}]}
            %%
            %% With the current implementation, the following will work in the
            %% nconf config:
            %%
            %%     {...,
            %%      main_key,
            %%      key,
            %%      value}
            %%
            %% Therefore when we have a tuple (like the 4-tuple above), we
            %% should follow the last element of the tuple.
            LastElement = element(size(OldTuple), OldTuple),
            case replace(LastElement, PathRest, Replacement) of
                {ok, NewLastElement} ->
                    NewTuple =
                        setelement(size(OldTuple), OldTuple, NewLastElement),
                    NewTupleList =
                        lists:keyreplace(Key, 1, OldTupleList, NewTuple),
                    {ok, NewTupleList};
                {error, {tuple_list_expected, Keys, OldValue}} ->
                    {error, {tuple_list_expected, [Key|Keys], OldValue}}
            end
    end;

replace(OldValue, [Key|_], _Replacement) ->
    {error, {tuple_list_expected, [Key], OldValue}}.

%%------------------------------------------------------------------------------
%% @doc Return the list dropping its last element.
%%
%% Copied from lists:droplast, which was added to OTP in 17.0.
%% @end
%%------------------------------------------------------------------------------
-spec droplast(List :: [T, ...]) -> [T] when T :: term().
droplast([_T])    -> [];
droplast([H | T]) -> [H | droplast(T)].

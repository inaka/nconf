%%%=============================================================================
%%% @copyright 2015, Erlang Solutions Ltd
%%% @doc Unit test
%%% @end
%%%=============================================================================
-module(nconf_test).
-copyright("2015, Erlang Solutions Ltd.").

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

%% Test file used during the tests.
-define(TEST_FILE, "nconf_config_test_file.nconf").
-define(TEST_FILE_CONTENTS, <<"{a, 1}.\n{b, 2}.">>).

-define(assertEqualSorted(A, B), ?assertEqual(lists:sort(A), lists:sort(B))).

%%%=============================================================================
%%% Test functions
%%%=============================================================================

self_test() ->
    %% We don't have any config params when started.
    ?assertEqualSorted([], get_all_env()),

    %% Setting non-empty config params.
    set_all_env([{a, 1}, {b, 2}]),
    ?assertEqualSorted([{a, 1}, {b, 2}], get_all_env()),

    %% Clearing the config params.
    set_all_env([]),
    ?assertEqualSorted([], get_all_env()).

read_config_test() ->

    %% Basic test
    file:delete(?TEST_FILE),
    file:write_file(?TEST_FILE, ?TEST_FILE_CONTENTS),
    ?assertEqual({ok, [{a, 1}, {b, 2}]}, nconf:read_config(?TEST_FILE)),

    %% Non-existing file
    file:delete(?TEST_FILE),
    Expected1 = {error, {enoent, "no such file or directory"}},
    ?assertEqual(Expected1, nconf:read_config(?TEST_FILE)),

    %% Bad file according to file:consult
    file:delete(?TEST_FILE),
    file:write_file(?TEST_FILE, <<"not erlang terms">>),
    {error, {ObtainedReason, ReasonStr}} = nconf:read_config(?TEST_FILE),
    Expected2 = {1,erl_parse,["syntax error before: ","terms"]},
    Expected3 = <<"1: syntax error before: terms">>,
    ?assertEqual(Expected2, ObtainedReason),
    ?assertEqual(Expected3, unicode:characters_to_binary(ReasonStr)).

apply_config_tuples_test() ->

    %% 01 No config tuple
    set_all_env([]),
    ?assertEqual(ok, nconf:apply_config_tuples([])),
    ?assertEqualSorted([], get_all_env()),

    %% 02 Setting full config params (i.e. we use 3 long config tuples)
    set_all_env([{existing_param_a, 1}, {existing_param_b, 2}]),
    NConf02 =
      [ {set, my_test_app, existing_param_a, 11}
      , {set, my_test_app, new_param, 33}
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf02)),

    Expected02 =
      [ {existing_param_a, 11}
      , {existing_param_b, 2}
      , {new_param, 33}
      ],
    ?assertEqualSorted(Expected02, get_all_env()),

    %% 03 Deleting full config params (i.e. we use 2 long config tuples)
    set_all_env([{existing_param_a, 1}, {existing_param_b, 2}]),

    NConf03 =
      [ {unset, my_test_app, existing_param_a}
      , {unset, my_test_app, new_param}
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf03)),

    Expected03 = [{existing_param_b, 2}],
    ?assertEqualSorted(Expected03, get_all_env()),

    %% 04 Setting deep config params: Update existing values
    Env04 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z, old }
                  , { z2, 2 }
                  ]
                }
              , { y2, 3 }
              ] } ] } ],
    set_all_env(Env04),

    NConf04 =
      [ { set, my_test_app, existing_param_a, x, 11 }
      , { set, my_test_app, existing_param_a, z, 33 }
      , { set, my_test_app, existing_param_b, x, y, z, new }
      , { set, my_test_app, existing_param_b, x, y2, new2 }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf04)),

    Expected04 =
      [ { existing_param_a
        , [ { z, 33 }
          , { x, 11 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z, new }
                  , { z2, 2 }
                  ] }
              , { y2, new2 }
              ] } ] } ],
    ?assertEqualSorted(Expected04, get_all_env()),

    %% 05 Replacing deep config params: Update existing values
    Env05 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z, old }
                  , { z2, 2 }
                  ] }
              , { y2, 3 }
              ] } ] } ],
    set_all_env(Env05),

    NConf05 =
      [ { replace, my_test_app, existing_param_a, x, { x, 1, 1 } }
      , { replace, my_test_app, existing_param_a, z, { z, 3, 3 } }
      , { replace, my_test_app, existing_param_b, x, y, z, { z, new, new } }
      , { replace, my_test_app, existing_param_b, x, y2, { y2, new2, new2 } }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf05)),

    Expected05 =
      [ { existing_param_a
        , [ { z, 3, 3 }
          , { x, 1, 1 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y2, new2, new2 }
              , { y
                , [ { z, new, new }
                  , { z2, 2 }
                  ] } ] } ] } ],
    ?assertEqualSorted(Expected05, get_all_env()),

    %% 06 Deleting deep config params: Deleting existing values
    Env06 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
        , { existing_param_b
          , [ { x1, 1 }
            , { x
              , [ { y
                  , [ { z, old }
                    , { z2, 2 }
                    ] }
                , { y2, 3 }
                ] } ] } ],
    set_all_env(Env06),

    NConf06 =
      [ { unset, my_test_app, existing_param_a, x }
      , { unset, my_test_app, existing_param_a, z }
      , { unset, my_test_app, existing_param_b, x, y, z }
      , { unset, my_test_app, existing_param_b, x, y2 }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf06)),

    Expected06 =
      [ { existing_param_a, [{y, 2}] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z2, 2 }
                  ] } ] } ] } ],
    ?assertEqualSorted(Expected06, get_all_env()),

    %% 07 Setting deep config params: Add new values to existing params
    Env07 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z, old }
                  , { z2, 2 }
                  ] }
              , { y2, 3 }
              ] } ] } ],
    set_all_env(Env07),

    NConf07 =
      [ { set, my_test_app, existing_param_b, x_new, 0 }
      , { set, my_test_app, existing_param_b, x, y_new, 0 }
      , { set, my_test_app, existing_param_b, x, y, z_new3, 0 }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf07)),

    Expected07 =
      [ { existing_param_a
      , [ { x, 1 }
        , { y, 2 }
        ] }
      , { existing_param_b
        , [ { x_new, 0 }
          , { x1, 1 }
          , { x
            , [ { y_new, 0 }
              , { y
                , [{z_new3, 0}, {z, old}, {z2, 2}]}, {y2, 3}]}]}],
    ?assertEqualSorted(Expected07, get_all_env()),

    %% 08 Replacing deep config params: Add new values to existing params
    Env08 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
      , { existing_param_b
        , [ { x1, 1 }
          , { x
            , [ { y
                , [ { z, old }
                  , { z2, 2 }
                  ] }
              , { y2, 3 }
              ] } ] } ],
    set_all_env(Env08),

    NConf08 =
      [ { replace, my_test_app, existing_param_b, x_new, { x_new, 0 } }
      , { replace, my_test_app, existing_param_b, x, y_new, { y_new, 0 } }
      , { replace, my_test_app, existing_param_b, x, y, z_new3, { z_new3, 0 } }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf08)),

    Expected08 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
        , { existing_param_b
          , [ { x_new, 0 }
            , { x1, 1 }
            , { x
              , [ { y_new, 0 }
                , { y
                  , [ { z_new3, 0 }
                    , { z, old }
                    , { z2, 2 }
                    ] }
                , { y2, 3 }
                ] } ] } ],
    ?assertEqualSorted(Expected08, get_all_env()),

    %% 09 Setting deep config params: Add new values to new params
    set_all_env([{existing_param_a, [{x, 1}, {y, 2}]}]),
    NConf09 =
      [ { set, my_test_app, new_param_a, a, 1 }
      , { set, my_test_app, new_param_b, b, bb, 2 }
      , { set, my_test_app, new_param_c, c, cc, ccc, 3 }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf09)),

    Expected09 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
      , { new_param_a
        , [ { a, 1 }
          ] }
      , { new_param_b
        , [ { b
            , [ { bb, 2 }
              ] } ] }
        , { new_param_c
          , [ { c
            , [ { cc
                , [ { ccc, 3 }
                  ] } ] } ] } ],
    ?assertEqualSorted(Expected09, get_all_env()),

    %% 10 Replacing deep config params: Add new values to new params
    set_all_env([{existing_param_a, [{x, 1}, {y, 2}]}]),
    NConf10 =
      [ { replace, my_test_app, new_param_a, a, { a, 1 } }
      , { replace, my_test_app, new_param_b, b, bb, { bb, 2 } }
      , { replace, my_test_app, new_param_c, c, cc, ccc, { ccc, 3 } }
      ],
    ?assertEqual(ok, nconf:apply_config_tuples(NConf10)),
    Expected10 =
      [ { existing_param_a
        , [ { x, 1 }
          , { y, 2 }
          ] }
        , { new_param_a
          , [ { a, 1 }
            ] }
        , { new_param_b
          , [ { b
              , [ { bb, 2 }
                ] } ] }
        , { new_param_c
          , [ { c
              , [ { cc
                  , [ { ccc, 3 }
                    ] } ] } ] } ],
    ?assertEqualSorted(Expected10, get_all_env()),

    %% 11 Test errors; and test the fact that if there is an error, other settings
    %% are still performed.
    set_all_env([{existing_param_a, [{x, 1}, {y, 2}]}]),
    Error11 =
      { error
      , [ { { tuple_list_expected
            , [ y, y2 ]
            , 2
            }
          , { set, my_test_app, existing_param_a, y, y2, 2 }
          } ] },
    NConf11 =
      [ { set, my_test_app, existing_param_a, y, y2, 2 }
      , { set, my_test_app, existing_param_a, x, 11 }
      ],
    ?assertEqual(Error11, nconf:apply_config_tuples(NConf11)),
    Expected11 = [ { existing_param_a, [ {x, 11 }, { y, 2 } ] } ],
    ?assertEqualSorted(Expected11, get_all_env()),

    %% 12
    set_all_env([ { existing_param_a, [ { x, 1 }, { y, 2 } ] } ] ),
    Error12 =
      { error
      , [ { not_a_tuple, [something] }
        , { tuple_too_short, { set, my_test_app, param } }
        , { tuple_too_short, { unset, my_test_app } }
        , { { unknown_command, mycmd }, { mycmd, x } }
        ]
      },
    NConf12 =
      [ [ something ]
      , { set, my_test_app, existing_param_a, x, 11 }
      , { set, my_test_app, param }
      , { unset, my_test_app }
      , { mycmd, x }
      ],
    ?assertEqual(Error12, nconf:apply_config_tuples(NConf12)),
    Expected12 = [ { existing_param_a, [ { x, 11 }, { y, 2 } ] } ],
    ?assertEqualSorted(Expected12, get_all_env()),

    %% 13 A 'replace' command needs to have at least one Path component, since the
    %% AppName/ParamName itself cannot be replaced with a custom term.
    set_all_env([ { existing_param_a, [ { x, 1 }, { y, 2 } ] } ] ),

    Error13 =
      { error
      , [ { tuple_too_short
          , { replace, my_test_app, existing_param_a, { existing_param_a, 2 } }
          } ] },
    NConf13 =
      [ { replace, my_test_app, existing_param_a, { existing_param_a, 2 } } ],
    ?assertEqual(Error13, nconf:apply_config_tuples(NConf13)),
    Expected13 = [ { existing_param_a, [ { x, 1 }, { y, 2 } ] } ],
    ?assertEqualSorted(Expected13, get_all_env()),
    ok.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

%%------------------------------------------------------------------------------
%% @doc Get the list of config parameters for the my_test_app application.
%% @end
%%------------------------------------------------------------------------------
-spec get_all_env() -> [{Par :: atom(), Val :: term()}].
get_all_env() ->
    application:get_all_env(my_test_app).

%%------------------------------------------------------------------------------
%% @doc Set the list of config parameters for the my_test_app application.
%% @end
%%------------------------------------------------------------------------------
-spec set_all_env([{Par :: atom(), Val :: term()}]) -> any().
set_all_env(NewConfigParams) ->
    %% Delete all existing config params.
    [  application:unset_env(my_test_app, Par)
    || {Par, _Val} <- application:get_all_env(my_test_app)
    ],

    %% Set the new config params.
    [  application:set_env(my_test_app, Par, Val)
    || {Par, Val} <- NewConfigParams
    ].

-endif.

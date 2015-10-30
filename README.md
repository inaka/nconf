# nconf

Nested Configuration Manager for Erlang Applications

`nconf` is a module for reading the contents of an nconf config file and
modifying the configuration parameters accordingly.

The following commands are available in an nconf config file:

```erlang
  {set, AppName, ParamName, Path1, ..., PathN, Replacement}
  {replace, AppName, ParamName, Path1, ..., PathN, Replacement}
  {unset, AppName, ParamName, Path1, ..., PathN}
```

## Example

Assume that we have an application that configures some ports and passwords to
be used in `sys.config`:

```erlang
[{myapp,
   [{ports,
       [{ftp, 21},
        {ssh, 22},
        {http, 80},
        {ssl, 443},
        {snmp, 161}],
    {passwords,
        [{"user1", "pw1"},
         {"user2", "pw2"}]}}].
```

**How can users modify the settings**? Let's say a user wants to set the http
port to 8080, delete the second password and add a third one. The options are the
following:

1. The user can modify the `sys.config` file itself. This is often not
   desirable, e.g. when the sys.config is a generated file, or when the next
   release of our application might contain a different sys.config file with
   additional default values.

2. The user can create a `user.config` file, use the [-config][1] option when
   starting `erl`, and thus have the configuration described in `sys.config`
   updated with the contents of `user.config`. The problem is that configuration
   values in the `user.config` file will overwrite the values in the
   `sys.config` files instead of being merged. So the user would need to repeat
   each configuration parameter in `sys.config` that needs to be updated (such
   as `ports` and `passwords`):

   ```erlang
   [{myapp,
      [{ports,
          [{ftp, 21},
           {ssh, 22},
           {http, 8080},
           {ssl, 443},
           {snmp, 161}],
       {passwords,
           [{"user1", "pw1"},
            {"user3", "pw3"}]}}].
   ```

3. Finally, **the user can use nconf** and write the following nconf
   configuration file:

   ```erlang
   {set, myapp, ports, http, 80}.
   {unset, myapp, passwords, "user2"}.
   {set, myapp, passwords, "user3", "pw3"}.
   ```

[1]: http://www.erlang.org/doc/man/config.html

## Details

The configuration entries are organized into a tree. The nconf config file
contains a number of tuples, each of which modifies one leaf or branch of this
tree. Leaves and branches can be replaced (with the `set` and `replace`
commands) and deleted (with the `unset` command). The elements of the tuple
(after the command) specify the path from the root of the configuration tree
towards the leaf or branch to be modified or deleted. In case of the `set` and
`replace` commands, the last element of the tuple defines the new value for the
leaf or branch.

The available commands in `wombat.config` are the following:

```erlang
{set, AppName, ParamName, Path1, ..., PathN, Replacement}.
```

Sets the value of a given configuration entry to the given value.

```erlang
{replace, AppName, ParamName, Path1, ..., PathN, Replacement}.
```

Sets a given configuration entry to the given value. The difference between
`set` and `replace` is that the former sets only the value, while the latter the
entry itself. Compare `{set, myapp, myparam, a, 1}` and `{replace, myapp,
myparam, a, {a, 1}}`, which perform the same task. The latter can be used to
set not only a pair, but also a longer tuple as a configuration entry; for
example the effect of `{replace, myapp, myparam, a, {a, 1, 2}}` cannot be
reproduced with `set`. Generally it is a good practice to use `set` whenever
possible, and use `replace` only when necessary.

```erlang
{unset, AppName, ParamName, Path1, ..., PathN}.
```

Deletes the given configuration entry.

# nconf
Nested Configuration Manager for Erlang Applications

`nconf` is a module for reading the contents of an nconf config file and
modifying the configuration parameters accordingly.

The following commands are available in an nconf config file:

```
  {set, AppName, ParamName, Path1, ..., PathN, Replacement}
  {replace, AppName, ParamName, Path1, ..., PathN, Replacement}
  {unset, AppName, ParamName, Path1, ..., PathN}
```

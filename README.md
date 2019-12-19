[![Hex.pm](https://img.shields.io/hexpm/v/quaff.svg?style=flat-square)](https://hex.pm/packages/quaff) 
[![Build Status](https://travis-ci.org/aruki-delivery/quaff.svg?branch=master)](https://travis-ci.org/github/aruki-delivery/quaff)
[![Inline docs](https://inch-ci.org/github/aruki-delivery/quaff.svg)](http://inch-ci.org/aruki-delivery/quaff?branch=master)

Quaff
=====

Quaff is a set of tools for integrating Elixir into erlang applications (or vice versa).

All contributions are welcome.

Installation
=====

Using [hex.pm](https://hex.pm/packages/quaff) (recommended way)

Simply add ```{:quaff, "~> 1.0"}``` to your project's ```mix.exs``` file, in the dependencies list and run ```mix 
deps.get quaff```.

### Example
```elixir
defp deps do
  [{:quaff, "~> 1.0"},]
end
```


Quaff
---------------

This module parses erlang header files, and imports any constants as `@` attributes. A constant means a `-define` macro which evaluates to a constant term, and takes no arguments (though it may use macros which accept arguments).  Constants whose names start with a capital letter will have an underscore prepended, for compatibility with Elixir syntax.

app/include/app_header.hrl:

```erlang
-define(CONSTANT_FROM_APP,5)
```

lib/mymodule.ex:

```elixir
defmodule MyModule
   require Quaff
   Quaff.include_lib("app/include/app_header.hrl")

   def myfunc() do
     @_CONSTANT_FROM_APP + 10
   end
end
```

Quaff.Debug
-----------

The Debug module provides a simple helper interface for running Elixir code in the erlang graphical debugger, using the technique I described in [this posting](http://qhool.github.io/elixir/2014/02/06/elixir-debug.html).

```
Interactive Elixir (0.12.2) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)>  Quaff.Debug.start() #start the graphical debugger
{:ok, #PID<0.59.0>}
iex(2)>  Quaff.Debug.load("./lib/mymodule.ex") #load all modules in source file
lib/mymodule.ex:1: redefining module My.Module
lib/mymodule.ex:212: redefining module My.OtherModule
[module: My.Module, module: My.OtherModule]
iex(3)>  Quaff.Debug.load(Yet.AnotherModule) #load a module by name
{:module, Yet.AnotherModule}
```

Also provided is `nload(module)` (equivalent to `load(module, all_nodes: true)`), which debugs the module[s] on all known nodes.

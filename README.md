Quaff
=====

Quaff is a set of tools for integrating Elixir into erlang applications (or vice versa).

Quaff.Constants
---------------

This module parses erlang header files, and imports any constants as `@` attributes. A constant means a `-define` macro which evaluates to a constant term, and takes no arguments (though it may use macros which accept arguments).  Constants whose names start with a capital letter will have an underscore prepended, for compatibility with Elixir syntax.

app/include/app_header.hrl:

    -define(CONSTANT_FROM_APP,5)

lib/mymodule.ex:

    defmodule MyModule
       require Quaff.Constants
       Quaff.Constants.include_lib("app/include/app_header.hrl")

       def myfunc() do
         @_CONSTANT_FROM_APP + 10
       end
    end




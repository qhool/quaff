defmodule Quaff.Constants.Test do
  use ExUnit.Case

  require Quaff.Constants
  alias Quaff.Constants, as: C

  #simple test headers
  C.include("test1.hrl", export: true)
  C.include("test2.hrl")
  C.include("test3_inc.hrl")
  #include various headers from otp, to sanity check basic parsing
  C.include_lib("eunit/include/eunit.hrl")
  C.include_lib("kernel/include/dist.hrl")
  C.include_lib("stdlib/include/erl_compile.hrl")
  C.include_lib("kernel/include/file.hrl")
  #these files include others:
  C.include_lib("snmp/include/snmp_tables.hrl")
  C.include_lib("inets/include/httpd.hrl")
  C.include_lib("public_key/include/public_key.hrl")

  test "simple constants" do
    assert @_SIMPLE_1 == 1
    assert @simple_2 == 2
    assert @_MM == 'Elixir.Quaff.Constants.Test'
  end

  test "constant exporting" do
    assert @_SIMPLE_1 == __MODULE__._SIMPLE_1
    assert @simple_2 == __MODULE__.simple_2
    assert @_MM == __MODULE__._MM
  end

  test "includes, ifdef, clobbering" do
    assert @_TEST3 == :test_3_a
  end

  test "macro args" do
    assert @_USES_ARGS == 21
  end

  test "eunit include" do
    assert @_EUNIT_HRL == true
  end

  test "erlang includes" do
    # from dist.hrl:
    assert is_integer(@_DFLAG_PUBLISHED)
    assert is_integer(@_DFLAG_DIST_MONITOR)
  end
end

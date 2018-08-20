defmodule Quaff.Constants.Test do
  use ExUnit.Case

  require Quaff

  # simple test headers
  Quaff.include("test1.hrl", export: true)
  Quaff.include("test2.hrl")
  Quaff.include("test3_inc.hrl")
  # include various headers from otp, to sanity check basic parsing
  Quaff.include_lib("eunit/include/eunit.hrl")
  Quaff.include_lib("stdlib/include/erl_bits.hrl")
  Quaff.include_lib("stdlib/include/erl_compile.hrl")
  Quaff.include_lib("kernel/include/file.hrl")
  # these files include others:
  Quaff.include_lib("snmp/include/snmp_tables.hrl")
  Quaff.include_lib("inets/include/httpd.hrl")
  # C.include_lib("/public_key.hrl")
  Quaff.include_lib("public_key/include/public_key.hrl")

  # relative paths
  Quaff.include_lib(
    Path.expand("#{__DIR__}/../include/more_test.hrl"),
    include: Path.expand("#{__DIR__}/../include/")
  )

  Quaff.include_lib("../include/more_test.hrl")
  Quaff.include_lib("./test1.hrl")

  Quaff.include_lib(Path.absname("#{__DIR__}/../include/more_test.hrl"))

  test "simple constants" do
    assert @_SIMPLE_1 == 1
    assert @simple_2 == 2
    assert @_MM == 'Elixir.Quaff.Constants.Test'
  end

  test "dynamic path constants" do
    assert @_SIMPLE_3 == 3
    assert @simple_4 == 4
    assert @_MM == 'Elixir.Quaff.Constants.Test'
  end

  test "constant exporting" do
    assert _SIMPLE_1 == @_SIMPLE_1
    assert simple_2 == @simple_2
    assert _MM == @_MM
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
    # from erl_bits.hrl:
    assert is_atom(@_SYS_ENDIAN)
    assert is_integer(@_SIZEOF_CHAR)
    assert is_integer(@_SIZEOF_INT)
  end
end

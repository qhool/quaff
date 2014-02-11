defmodule Quaff.Constants.Test do
  use ExUnit.Case

  require Quaff.Constants

  Quaff.Constants.include_lib("quaff/include/test1.hrl")

  test "simple constants" do
    assert @_SIMPLE_1 == 1
    assert @simple_2 == 2
  end

end
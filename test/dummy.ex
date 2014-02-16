defmodule Dummy1 do
  def foo() do
    :ok
  end

  def bar() do
    foo()
  end
end

defmodule Dummy2 do
  def x() do
    1
  end
end
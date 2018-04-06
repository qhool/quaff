defmodule Quaff.Debug.Test do
  use ExUnit.Case

  require Quaff.Debug
  require Quaff.Constants
  alias Quaff.Debug, as: Dbg

  setup context do
    if context[:debugger] do
      :meck.new(:debugger)
      :meck.expect(:debugger,:start,fn() -> {:ok,self()} end)
    end
    if context[:int] do
      :meck.new(:int)
      :meck.expect(:int,:i,fn(_) -> :ok end)
      :meck.expect(:int,:ni,fn(_) -> :ok end)
    end
    on_exit(context,fn() ->
                        :meck.unload()
                    end)
    :ok
  end

  @tag :debugger
  test "debug start" do
    Dbg.start()
    assert :meck.called(:debugger,:start,[])
    assert :meck.validate(:debugger)
  end

  @tag :int
  test "interpret file" do
    Dbg.load("test/dummy.ex")
    assert dummy_was_loaded(:i)
    assert :meck.validate(:int)
  end

  @tag :int
  test "interpret file ni" do
    Dbg.nload("test/dummy.ex")
    assert dummy_was_loaded(:ni)
    assert :meck.validate(:int)
  end

  @tag :int
  test "interpret module" do
    Dbg.load(Quaff.Constants)
    ex_pat = Regex.compile!("constants\.ex$")
    beam_pat = Regex.compile!("Elixir\.Quaff\.Constants\.beam$")
    assert called_pattern(:int,:i,
                          fn([{Quaff.Constants,src,beam,bb}])
                            when is_binary(bb) ->
                              Regex.match?(ex_pat,
                                           List.to_string(src)) and
                              Regex.match?(beam_pat,
                                           List.to_string(beam))
                            (_) -> false
                          end)
    assert :meck.validate(:int)
  end

  def dummy_was_loaded(f) do
    called_pattern(:int,f,
                   fn([{Dummy1,'test/dummy.ex','Elixir.Dummy1.beam',bb}])
                     when is_binary(bb) ->
                       true
                     (_) -> false
                   end)
    called_pattern(:int,f,
                   fn([{Dummy2,'test/dummy.ex','Elixir.Dummy2.beam',bb}])
                     when is_binary(bb) ->
                       true
                     (_) -> false
                   end)
    true
  end


  def called_pattern(mod,f,scanner) do
    hist = :meck.history(mod)
    case Enum.reduce( hist, {[],false},
                      fn(_,{_,true}) ->
                          {nil,true}
                        ({_pid,{mod1,f1,args},_res},{checked,false}) when mod1 == mod and f1 == f ->
                          case scanner.(args) do
                            true -> {nil,true}
                            _ -> {[args|checked],false}
                          end
                        (_,acc) -> acc
                      end ) do
      {nil,true} ->
        true
      {calls,false} ->
        prn_calls = Enum.map(calls,
                             fn([{a,b,c,x}]) when byte_size(x) > 20 ->
                                 [{a,b,c,:"[binary]"}]
                               (x) -> x
                             end)
        :io.format("No matching call:~n~p~n",[prn_calls])
        false
    end
  end
end
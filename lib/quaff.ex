# Copyright 2018 Carlos Brito Lage <cbl@aruki.pt>

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Quaff do
  @moduledoc false

  require Logger

  defmodule CompileError do
    defexception message: nil

    def exception(opts) do
      file = opts[:file] || "<unknown file>"
      line = opts[:line] || -1
      msg = opts[:message] || List.to_string(:io_lib.format(opts[:format], opts[:items]))
      msg = msg <> List.to_string(:io_lib.format("~n  at ~s line ~p", [file, line]))
      %__MODULE__{message: msg}
    end
  end

  defmacro include(header) do
    quote do
      Quaff.include(unquote(header), [])
    end
  end

  defmacro include(header, options) do
    header =
      cond do
        :ok == Macro.validate(header) ->
          {hd, []} = header |> Code.eval_quoted([], __CALLER__)
          hd

        true ->
          header
      end

    use_constants = options[:constants] || :all
    do_export = options[:export] || false

    in_module =
      options[:module] ||
        Macro.expand(
          quote do
            __MODULE__
          end,
          __CALLER__
        )

    rel_dir =
      cond do
        options[:relative_to] && :ok == Macro.validate(options[:relative_to]) ->
          {rel_to, []} = options[:relative_to] |> Code.eval_quoted([], __CALLER__)
          rel_to

        options[:relative_to] ->
          options[:relative_to]

        true ->
          Macro.expand(
            quote do
              __DIR__
            end,
            __CALLER__
          )
      end

    inc_dir =
      cond do
        options[:include] && :ok == Macro.validate(options[:include]) ->
          {inc, []} = options[:include] |> Code.eval_quoted([], __CALLER__)
          inc

        options[:include] ->
          options[:include]

        true ->
          [
            Macro.expand(
              quote do
                __DIR__
              end,
              __CALLER__
            )
          ]
      end

    options = Keyword.put(options, :module, in_module)
    options = Keyword.put(options, :relative_to, rel_dir)
    options = Keyword.put(options, :include, inc_dir)

    const =
      Enum.map(Quaff.Constants.get_constants(header, options), fn {c, v} ->
        {Quaff.Constants.normalize_const(c), v}
      end)

    const =
      case use_constants do
        :all ->
          const

        _ ->
          Enum.map(List.wrap(use_constants), fn c ->
            c = Quaff.Constants.normalize_const(c)
            {c, Keyword.fetch!(const, c)}
          end)
      end

    attrs =
      Enum.map(const, fn {c, val} ->
        quote do
          Module.put_attribute(__MODULE__, unquote(c), unquote(Macro.escape(val)))
        end
      end)

    funs =
      case do_export do
        true ->
          Enum.map(const, fn {c, _} ->
            {:ok, ident} = Code.string_to_quoted(Atom.to_string(c))

            quote do
              def unquote(ident) do
                @unquote ident
              end
            end
          end)

        _ ->
          []
      end

    attrs ++ funs
  end

  defmacro include_lib(header) do
    quote do
      Quaff.include_lib(unquote(header), [])
    end
  end

  defmacro include_lib(header, options) do
    opts =
      options
      |> Macro.expand_once(__CALLER__)
      |> Keyword.put(:include_lib, true)

    quote do
      Quaff.include(unquote(header), unquote(opts))
    end
  end

end

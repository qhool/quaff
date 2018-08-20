# Copyright 2014 Josh Burroughs <josh@qhool.com>

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

# http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Quaff.Debug do
  def start() do
    :debugger.start()
  end

  def load(module) do
    load(module, [])
  end

  def load(module, options) when is_atom(module) do
    case Atom.to_string(module) do
      "Elixir." <> _ ->
        load_ex(module, options)

      _ ->
        call_i(module, options)
    end
  end

  def load(src, options) when is_binary(src) do
    case String.reverse(src) do
      "xe." <> _ ->
        load_ex(src, options)

      _ ->
        call_i(src, options)
    end
  end

  def nload(module) do
    nload(module, [])
  end

  def nload(module, options) do
    load(module, Keyword.put(options, :all_nodes, true))
  end

  defp load_ex(module, options) when is_atom(module) do
    mod_info = module.module_info()
    compiled_src = mod_info[:compile][:source]
    {^module, beam_bin, beam_file} = :code.get_object_code(module)
    # TODO: use code path to search for src  --OR--
    #      add source option
    # basename = :filename.basename(compiled_src)
    call_i({module, compiled_src, beam_file, beam_bin}, options)
  end

  defp load_ex(src, options) when is_binary(src) do
    mods = Code.load_file(src)

    Enum.map(mods, fn {mod, beam_bin} ->
      call_i({mod, String.to_charlist(src), Atom.to_charlist(mod) ++ '.beam', beam_bin}, options)
    end)
  end

  defp call_i(arg, options) do
    case Keyword.get(options, :all_nodes, false) do
      true -> :int.ni(arg)
      false -> :int.i(arg)
    end
  end
end

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
defmodule Quaff.Constants do
  require Record
  require Logger

  def normalize_const(a) when is_atom(a) do
    normalize_const(Atom.to_string(a))
  end

  def normalize_const(name) do
    (c = name |> String.first()) |>
      String.upcase() |>
      case do
        ^c -> "_" <> name
        _ -> name
      end |>
      String.to_atom()
  end

  def get_constants(header_file) do
    get_constants(header_file, [])
  end

  def get_constants(header_file, options) do
    incl_type =
      case options[:include_lib] do
        true -> :macro_include_lib
        _ -> :macro_include
      end

    in_module = options[:module] || caller_module() || __MODULE__
    relative_dir = options[:relative_to] || System.cwd()

    include_dirs =
      List.flatten([Keyword.get_values(options, :include), Keyword.get_values(options, :i)])

    include_dirs = Enum.map(include_dirs, fn d -> Path.expand(d, relative_dir) end)

    {:ok, abs_header, tree} =
      read_header(
        header_file,
        inc_type: incl_type,
        relative_to: relative_dir,
        include_path: include_dirs,
        from_file: "x",
        from_line: -1
      )

    ctx = init_ctx(in_module, abs_header, include_dirs)
    defs = find_defns(tree, ctx)

    Enum.flat_map(defs, fn {macro, all_arity} ->
      case Map.get(all_arity, 0) do
        nil ->
          []

        {[], defn} ->
          case parse_constant(defn) do
            nil -> []
            val -> [{macro, val}]
          end
      end
    end)
  end

  defp parse_constant(defn) do
    case :erl_parse.parse_exprs(defn ++ [{:dot, 0}]) do
      {:ok, exprs} ->
        case :erl_eval.exprs(exprs, []) do
          {:value, val, _} ->
            case has_funs?(val) do
              true -> nil
              _ -> val
            end

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  # funs don't appear to work as module attrs
  defp has_funs?(f) when is_function(f) do
    true
  end

  defp has_funs?(ls) when is_list(ls) do
    Enum.any?(ls, &has_funs?/1)
  end

  defp has_funs?(t) when is_tuple(t) do
    has_funs?(Tuple.to_list(t))
  end

  defp has_funs?(_) do
    false
  end

  defp read_header(
         header_file,
         inc_type: incl_type,
         relative_to: relative_dir,
         include_path: include_path,
         from_file: from_file,
         from_line: from_line
       ) do
    {:ok, realfile} =
      case resolve_include(incl_type, header_file, relative_dir, include_path) do
        {:ok, _} = res ->
          res

        {:error, {:not_found, _}} ->
          raise(
            Quaff.CompileError,
            format: "Can't locate header ~s~n relative to: ~s~n include path was: ~p",
            items: [header_file, relative_dir, include_path],
            file: from_file,
            line: from_line
          )
      end

    {:ok, contents} =
      case File.read(realfile) do
        {:ok, _} = res ->
          res

        {:error, reason} ->
          raise(
            Quaff.CompileError,
            format: "Error reading ~s: ~p",
            items: [realfile, reason],
            file: from_file,
            line: from_line
          )
      end

    contents = String.to_charlist(contents)
    {:ok, h_toks, _} = :erl_scan.string(contents, {1, 1})
    tokens = mark_keywords(h_toks)
    {:ok, toks} = :aleppo_parser.parse(tokens)
    {:ok, realfile, toks}
  end

  # this does not work correctly for tail calls
  defp caller_module() do
    trace =
      try do
        throw(:not_a_problem)
      catch
        :not_a_problem ->
          :erlang.get_stacktrace()
      end

    modules = Enum.map(trace, fn {m, _, _, _} -> m end)

    List.first(
      Enum.filter(modules, fn
        __MODULE__ ->
          false

        _ ->
          true
      end)
    )
  end

  defp resolve_include(incl_type, file, rel, incl_path) when is_list(file) do
    resolve_include(incl_type, List.to_string(file), rel, incl_path)
  end

  defp resolve_include(:macro_include_lib, "/" <> _ = abs_file, _, _) do
    case File.exists?(abs_file) do
      true ->
        {:ok, abs_file}

      _ ->
        {:error, {:not_found, abs_file}}
    end
  end

  defp resolve_include(:macro_include_lib, "./" <> _ = rel_file, rel, _) do
    unrelative = Path.expand(rel_file, rel)

    case File.exists?(unrelative) do
      true ->
        {:ok, unrelative}

      _ ->
        {:error, {:not_found, unrelative}}
    end
  end

  defp resolve_include(:macro_include_lib, "../" <> _ = rel_file, rel, _) do
    unrelative = Path.expand(rel_file, rel)

    case File.exists?(unrelative) do
      true ->
        {:ok, unrelative}

      _ ->
        {:error, {:not_found, unrelative}}
    end
  end

  defp resolve_include(:macro_include_lib, file, _, _) do
    # TODO make macro to generate is_windows based on drive_list
    is_window_file = fn f ->
      f
      |> case do
        "c:/" <> _ -> true
        _ -> false
      end
    end

    cond do
      is_window_file.(file) ->
        resolve_windows_include = fn :macro_include_lib ->
          file
          |> File.exists?()
          |> case do
            true ->
              {:ok, file}

            _ ->
              {:error, {:not_found, file}}
          end
        end

        resolve_windows_include.(:macro_include_lib)

      true ->
        [app_name | file_path] = :filename.split(String.to_charlist(file))

        case :code.lib_dir(List.to_atom(app_name)) do
          {:error, _} ->
            {:error, {:not_found, file}}

          app_lib ->
            {:ok, List.to_string(:filename.join([app_lib | file_path]))}
        end
    end
  end

  defp resolve_include(:macro_include, file, rel, incl_path) do
    resolve_include(file, rel, incl_path)
  end

  defp resolve_include("$" <> incl, rel, incl_path) do
    [_, var_name, suff] = Regex.run(Regex.compile!("(\w+)(.*)$"), incl)
    resolve_include((System.get_env(var_name) || "") <> suff, rel, incl_path)
  end

  defp resolve_include("/" <> _ = abs_file, _, _) do
    case File.exists?(abs_file) do
      true ->
        {:ok, abs_file}

      _ ->
        {:error, {:not_found, abs_file}}
    end
  end

  defp resolve_include(file, relative_to, include_path) when is_binary(relative_to) do
    unrelative = Path.expand(file, relative_to)

    case File.exists?(unrelative) do
      true ->
        {:ok, unrelative}

      _ ->
        case file do
          "./" <> _ -> {:error, {:not_found, file}}
          "../" <> _ -> {:error, {:not_found, file}}
          _ -> resolve_include(file, include_path)
        end
    end
  end

  defp resolve_include(file, [inc | include_path]) do
    full = Path.expand(file, inc)

    case File.exists?(full) do
      true ->
        {:ok, full}

      _ ->
        resolve_include(file, include_path)
    end
  end

  defp resolve_include(file, []) do
    # last ditch effort
    case :code.where_is_file(String.to_charlist(file)) do
      :non_existing -> {:error, {:not_found, file}}
      filename -> {:ok, List.to_string(filename)}
    end
  end

  defp expand_nested(tokens, ctx) do
    expand_nested(tokens, [], ctx)
  end

  defp expand_nested([], acc, _) do
    Enum.reverse(acc)
  end

  defp expand_nested([{:macro, {_, loc, :LINE}} | tokens], acc, ctx) do
    line =
      case loc do
        {line, _col} -> line
        _ -> loc
      end

    expand_nested(tokens, [{:integer, loc, line} | acc], ctx)
  end

  defp expand_nested([{:macro, {_, _, name}} | tokens], acc, ctx) do
    {[], def_toks} = get_def(ctx, {name, 0})
    expand_nested(tokens, Enum.reverse(def_toks) ++ acc, ctx)
  end

  defp expand_nested([{:macro, {_, _, name}, args} | tokens], acc, ctx) do
    {arg_names, def_toks} = get_def(ctx, {name, length(args)})
    arg_mapping = List.zip([arg_names, args])

    filled_in =
      Enum.flat_map(def_toks, fn
        {:var, _, varname} = tok ->
          case Keyword.get(arg_mapping, varname) do
            nil -> [tok]
            replacement -> replacement
          end

        tok ->
          [tok]
      end)

    expand_nested(tokens, Enum.reverse(filled_in) ++ acc, ctx)
  end

  defp expand_nested([other | tokens], acc, ctx) do
    expand_nested(tokens, [other | acc], ctx)
  end

  defp find_defns([], ctx) do
    defs_list(ctx)
  end

  defp find_defns([{:eof, _} | tree], ctx) do
    find_defns(tree, pop_file(ctx))
  end

  defp find_defns([{:macro_define, {_, _, name}} | tree], ctx) do
    find_defns(tree, put_def(ctx, {name, 0}, {[], true}))
  end

  defp find_defns([{:macro_define, {_, _, name}, toks} | tree], ctx) do
    expanded = expand_nested(toks, ctx)
    find_defns(tree, put_def(ctx, {name, 0}, {[], expanded}))
  end

  defp find_defns([{:macro_define, {_, _, name}, args, toks} | tree], ctx) do
    expanded = expand_nested(toks, ctx)

    arg_names =
      Enum.map(args, fn [{:var, _, var_name}] ->
        var_name
      end)

    find_defns(tree, put_def(ctx, {name, length(args)}, {arg_names, expanded}))
  end

  defp find_defns([{:macro_undef, {_, _, name}} | tree], ctx) do
    find_defns(tree, rm_def(ctx, name))
  end

  defp find_defns([{incl_type, {:string, loc, file}} | tree], ctx)
       when incl_type in [:macro_include, :macro_include_lib] do
    {current_file, dir, includes} = get_paths(ctx)

    line =
      case loc do
        {ln, _} -> ln
        ln -> ln
      end

    {:ok, abs_file, subtree} =
      read_header(
        file,
        inc_type: incl_type,
        relative_to: dir,
        include_path: includes,
        from_file: current_file,
        from_line: line
      )

    find_defns(subtree ++ tree, push_file(ctx, abs_file))
  end

  defp find_defns([{:macro_ifdef, x, ifbody} | tree], ctx) do
    find_defns([{:macro_ifdef, x, ifbody, []} | tree], ctx)
  end

  defp find_defns([{:macro_ifndef, x, ifbody} | tree], ctx) do
    find_defns([{:macro_ifdef, x, [], ifbody} | tree], ctx)
  end

  defp find_defns([{:macro_ifndef, x, ifbody, elsebody} | tree], ctx) do
    find_defns([{:macro_ifdef, x, elsebody, ifbody} | tree], ctx)
  end

  defp find_defns([{:macro_ifdef, {_, _, name}, ifbody, elsebody} | tree], ctx) do
    case has_def?(ctx, name) do
      true -> find_defns(ifbody ++ tree, ctx)
      false -> find_defns(elsebody ++ tree, ctx)
    end
  end

  defp find_defns([_other | tree], ctx) do
    find_defns(tree, ctx)
  end

  defp mark_keywords(tokens) do
    mark_keywords(tokens, [])
  end

  defp mark_keywords([{:-, {_, 1}} = dash, {:atom, loc, kw} | tokens], out)
       when kw in [:define, :ifdef, :ifndef, :else, :endif, :undef, :include, :include_lib] do
    keyword = String.to_atom(Atom.to_string(kw) <> "_keyword")
    mark_keywords(tokens, [{keyword, loc}, dash | out])
  end

  defp mark_keywords([tok | tokens], out) do
    mark_keywords(tokens, [tok | out])
  end

  defp mark_keywords([], out) do
    Enum.reverse(out)
  end

  Record.defrecordp(:qc_ctx, [:defs, :files, :relative_dirs, :includes])

  ## defs dictionary:
  defp init_ctx() do
    qc_ctx(defs: Map.new(), files: [], relative_dirs: [], includes: [])
  end

  defp init_ctx(module, file, incls) do
    defs = [
      {{:MODULE, 0}, {[], [{:atom, {1, 1}, module}]}},
      {{:MODULE_STRING, 0}, {[], [{:string, {1, 1}, Atom.to_charlist(module)}]}}
    ]

    ctx = qc_ctx(init_ctx(), includes: incls)
    put_defs(push_file(ctx, file), defs)
  end

  defp push_file(
         qc_ctx(
           files: files,
           relative_dirs: rels,
           includes: incls
         ) = ctx,
         file
       ) do
    ctx = put_def(ctx, {:FILE, 0}, {[], [{:string, {1, 1}, file}]})
    dir = Path.dirname(file)
    new_incl = Path.expand("../include", dir)
    qc_ctx(ctx, files: [file | files], relative_dirs: [dir | rels], includes: [new_incl | incls])
  end

  defp pop_file(
         qc_ctx(
           files: [_ | files],
           relative_dirs: [_ | rels],
           includes: [_ | incls]
         ) = ctx
       ) do
    ctx =
      case files do
        [old_file | _] ->
          put_def(ctx, {:FILE, 0}, {[], [{:string, {1, 1}, old_file}]})

        [] ->
          ctx
      end

    qc_ctx(ctx, files: files, relative_dirs: rels, includes: incls)
  end

  defp get_paths(qc_ctx(files: [f | _], relative_dirs: [rel | _], includes: incls)) do
    {f, rel, incls}
  end

  defp get_def(qc_ctx(defs: defs), {name, arity}) do
    all_arity = Map.fetch!(defs, name)
    Map.fetch!(all_arity, arity)
  end

  defp defs_list(qc_ctx(defs: defs)) do
    Map.to_list(defs)
  end

  defp put_defs(ctx, defs) when is_list(defs) do
    Enum.reduce(defs, ctx, fn {d, defn}, subctx -> put_def(subctx, d, defn) end)
  end

  defp put_def(qc_ctx(defs: defs) = ctx, {name, arity}, defn) do
    all_arity =
      case Map.get(defs, name) do
        nil -> Map.new()
        aa -> aa
      end

    qc_ctx(ctx, defs: Map.put(defs, name, Map.put(all_arity, arity, defn)))
  end

  defp has_def?(qc_ctx(defs: defs), name) do
    Map.has_key?(defs, name)
  end

  defp rm_def(qc_ctx(defs: defs) = ctx, name) do
    qc_ctx(ctx, defs: Map.delete(defs, name))
  end
end

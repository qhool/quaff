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

  defexception CompileError, [:file, :line, :message] do
    def exception(opts) do
      file = opts[:file] || "<unknown file>"
      line = opts[:line] || -1
      msg = opts[:message] ||
      String.from_char_list!(:io_lib.format( opts[:format], opts[:items] ))
      msg = msg <> String.from_char_list!(:io_lib.format( "~n  at ~s line ~p", [file,line] ))
      CompileError[ message: msg, file: file, line: line ]
    end
  end

  defmacro include(header) do
    quote do
      Quaff.Constants.include(unquote(header),[])
    end
  end

  defmacro include(header, options) do
    use_constants = options[:constants] || :all
    do_export = options[:export] || false
    in_module = options[:module] || Macro.expand(quote do __MODULE__ end,__CALLER__)
    in_dir = options[:relative_to] || Macro.expand(quote do __DIR__ end, __CALLER__)
    options = Keyword.put(options,:module,in_module)
    options = Keyword.put(options,:relative_to,in_dir)
    const = Enum.map(get_constants(header,options),
                     fn({c,v}) ->
                         {normalize_const(c),v}
                     end)
    const = case use_constants do
              :all -> const
              _ ->
                Enum.map(List.wrap(use_constants),
                              fn(c) ->
                                  c = normalize_const(c)
                                  {c,Dict.fetch!(const,c)}
                              end
                        )
            end
    attrs =
      Enum.map( const,
                fn({c,val}) ->
                    quote do
                      Module.put_attribute(__MODULE__, unquote(c),
                                           unquote(Macro.escape(val)))
                    end
                end)
    funs =
      case do_export do
        true ->
          Enum.map( const,
                    fn({c,_}) ->
                        {:ok,ident} =
                          Code.string_to_quoted(atom_to_binary(c))
                        quote do
                          def unquote(ident) do
                            @unquote(ident)
                          end
                        end
                    end )
        _ -> []
      end
    attrs ++ funs
  end

  defmacro include_lib(header) do
    quote do
      Quaff.Constants.include_lib(unquote(header),[])
    end
  end

  defmacro include_lib(header, options) do
    quote do
      Quaff.Constants.include(unquote(header),unquote(Keyword.put(options,:include_lib,true)))
    end
  end

  defp normalize_const(a) when is_atom(a) do
    normalize_const(atom_to_binary(a))
  end
  defp normalize_const(name) do
    c = String.first(name)
    normed_str =
      case String.upcase(c) do
        ^c -> "_"<>name
        _ -> name
      end
    binary_to_atom(normed_str)
  end

  def get_constants(header_file) do
    get_constants(header_file,[])
  end

  def get_constants(header_file,options) do
    incl_type = case options[:include_lib] do
                  true -> :macro_include_lib
                  _ -> :macro_include
                end
    in_module = options[:module] || caller_module() || __MODULE__
    relative_dir = options[:relative_to] || System.cwd
    include_dirs = List.flatten([Keyword.get_values(options,:include),
                                 Keyword.get_values(options,:i)])
    include_dirs = Enum.map(include_dirs,
                            fn(d) -> Path.expand(d,relative_dir) end)
    {:ok, abs_header, tree} = read_header(header_file, inc_type: incl_type,
                                                       relative_to: relative_dir,
                                                       include_path: include_dirs,
                                                       from_file: "x",
                                                       from_line: -1 )
    ctx = init_ctx(in_module,abs_header,include_dirs)
    defs = find_defns(tree,ctx)
    Enum.flat_map(defs,
                  fn({macro,all_arity}) ->
                      case Dict.get(all_arity,0) do
                        nil -> []
                        {[],defn} ->
                          case parse_constant(defn) do
                            nil -> []
                            val -> [{macro,val}]
                          end
                      end
                  end)
  end

  defp parse_constant(defn) do
    case :erl_parse.parse_exprs(defn++[{:dot,0}]) do
      {:ok, exprs} ->
        case :erl_eval.exprs(exprs,[]) do
          {:value, val, _} ->
            case has_funs?(val) do
              true -> nil
              _ -> val
            end
          _ -> nil
        end
      _ -> nil
    end
  end

  #funs don't appear to work as module attrs
  defp has_funs?(f) when is_function(f) do
    true
  end
  defp has_funs?(ls) when is_list(ls) do
    Enum.any?(ls,&has_funs?/1)
  end
  defp has_funs?(t) when is_tuple(t) do
    has_funs?(tuple_to_list(t))
  end
  defp has_funs?(_) do
    false
  end

  defp read_header(header_file, inc_type: incl_type,
                                relative_to: relative_dir,
                                include_path: include_path,
                                from_file: from_file,
                                from_line: from_line ) do
    {:ok,realfile} =
      case resolve_include(incl_type,header_file,relative_dir,include_path) do
        {:ok,_} = res -> res
        {:error,{:not_found,_}} ->
          raise( CompileError, format: "Can't locate header ~s~n relative to: ~s~n include path was: ~p",
                 items: [header_file,relative_dir,include_path],
                 file: from_file, line: from_line )
      end
    {:ok,contents} =
      case File.read(realfile) do
        {:ok,_} = res -> res
        {:error,reason} ->
          raise( CompileError, format: "Error reading ~s: ~p",
                 items: [realfile,reason],
                 file: from_file, line: from_line )
      end
    {:ok,contents} = String.to_char_list(contents)
    {:ok,h_toks,_} = :erl_scan.string(contents,{1,1})
    tokens = mark_keywords(h_toks)
    {:ok, toks} = :aleppo_parser.parse(tokens)
    {:ok, realfile, toks}
  end

  #this does not work correctly for tail calls
  defp caller_module() do
    trace =
      try do throw(:not_a_problem)
      catch :not_a_problem ->
              :erlang.get_stacktrace()
      end
    modules = Enum.map(trace,fn({m,_,_,_}) -> m end)
    List.first(Enum.filter(modules,fn(__MODULE__) ->
                                       false
                                     (_) ->
                                       true
                                   end))
  end

  defp resolve_include(incl_type,file,rel,incl_path) when is_list(file) do
    resolve_include(incl_type,String.from_char_list!(file),rel,incl_path)
  end
  defp resolve_include(:macro_include_lib,file,_,_) do
    [app_name|file_path] = :filename.split(String.to_char_list!(file))
    case :code.lib_dir(list_to_atom(app_name)) do
      {:error, _} ->
        {:error, {:not_found,file}}
      app_lib ->
        {:ok,iolist_to_binary(:filename.join([app_lib|file_path]))}
    end
  end
  defp resolve_include(:macro_include,file,rel,incl_path) do
    resolve_include(file,rel,incl_path)
  end

  defp resolve_include("$"<>incl,rel,incl_path) do
    [_,var_name,suff] = Regex.run( Regex.compile!("(\w+)(.*)$"), incl )
    resolve_include((System.get_env(var_name)||"")<>suff,rel,incl_path)
  end
  defp resolve_include(("/"<>_)=abs_file,_,_) do
    case File.exists?(abs_file) do
      true -> {:ok, abs_file}
      _ ->
        {:error, {:not_found,abs_file}}
    end
  end
  defp resolve_include(file,relative_to,include_path) when is_binary(relative_to) do
    unrelative = Path.expand(file,relative_to)
    case File.exists?(unrelative) do
      true -> {:ok, unrelative}
      _ ->
        case file do
          "./"<>_ -> {:error, {:not_found,file}}
          "../"<>_ -> {:error, {:not_found,file}}
          _ -> resolve_include(file,include_path)
        end
    end
  end
  defp resolve_include(file,[inc|include_path]) do
    full = Path.expand(file,inc)
    case File.exists?(full) do
      true -> {:ok, full}
      _ ->
        resolve_include(file,include_path)
    end
  end
  defp resolve_include(file,[]) do
    #last ditch effort
    case :code.where_is_file(String.to_char_list!(file)) do
          :non_existing -> {:error, {:not_found,file}}
          filename -> {:ok, iolist_to_binary(filename)}
    end
  end


  defp expand_nested(tokens,ctx) do
    expand_nested(tokens,[],ctx)
  end
  defp expand_nested([],acc,_) do
    Enum.reverse(acc)
  end
  defp expand_nested([{:macro,{_,loc,:LINE}}|tokens], acc, ctx) do
    line = case loc do
             {line,_col} -> line
             _ -> loc
           end
    expand_nested(tokens, [{:integer,loc,line}|acc], ctx)
  end
  defp expand_nested([{:macro,{_,_,name}}|tokens], acc, ctx) do
    {[],def_toks} = get_def(ctx,{name,0})
    expand_nested( tokens, Enum.reverse(def_toks) ++ acc, ctx)
  end
  defp expand_nested([{:macro,{_,_,name},args}|tokens], acc, ctx) do
    {arg_names,def_toks} = get_def(ctx,{name,length(args)})
    arg_mapping = ListDict.new(List.zip([arg_names,args]))
    filled_in =
      Enum.flat_map(def_toks,
                    fn({:var,_,varname}=tok) ->
                        case Dict.get(arg_mapping,varname) do
                          nil -> [tok]
                          replacement -> replacement
                        end
                      (tok) -> [tok]
                    end)
    expand_nested(tokens,Enum.reverse(filled_in)++acc,ctx)
  end
  defp expand_nested([other|tokens],acc,ctx) do
    expand_nested(tokens,[other|acc],ctx)
  end

  defp find_defns([],ctx) do
    defs_list(ctx)
  end
  defp find_defns([{:eof,_}|tree],ctx) do
    find_defns( tree, pop_file(ctx))
  end
  defp find_defns([{:macro_define,{_,_,name}}|tree],ctx) do
    find_defns( tree, put_def(ctx,{name,0},{[],true}) )
  end
  defp find_defns([{:macro_define,{_,_,name},toks}|tree],ctx) do
    expanded = expand_nested(toks,ctx)
    find_defns( tree, put_def(ctx,{name,0},{[],expanded}) )
  end
  defp find_defns([{:macro_define,{_,_,name},args,toks}|tree],ctx) do
    expanded = expand_nested(toks,ctx)
    arg_names = Enum.map(args,
                         fn([{:var,_,var_name}]) ->
                              var_name
                          end)
    find_defns( tree, put_def(ctx,{name,length(args)},{arg_names,expanded}) )
  end
  defp find_defns([{:macro_undef,{_,_,name}}|tree],ctx) do
    find_defns( tree, rm_def(ctx,name) )
  end
  defp find_defns([{incl_type,{:string,loc,file}}|tree],ctx)
  when incl_type in [:macro_include,:macro_include_lib] do
    {current_file,dir,includes} = get_paths(ctx)
    line = case loc do
             {ln,_} -> ln
             ln -> ln
           end
    {:ok,abs_file,subtree} = read_header(file, inc_type: incl_type,
                                         relative_to: dir,
                                         include_path: includes,
                                         from_file: current_file,
                                         from_line: line )
    find_defns(subtree++tree,push_file(ctx,abs_file))
  end
  defp find_defns([{:macro_ifdef,x,ifbody}|tree],ctx) do
    find_defns([{:macro_ifdef,x,ifbody,[]}|tree],ctx)
  end
  defp find_defns([{:macro_ifndef,x,ifbody}|tree],ctx) do
    find_defns([{:macro_ifdef,x,[],ifbody}|tree],ctx)
  end
  defp find_defns([{:macro_ifndef,x,ifbody,elsebody}|tree],ctx) do
    find_defns([{:macro_ifdef,x,elsebody,ifbody}|tree],ctx)
  end
  defp find_defns([{:macro_ifdef,{_,_,name},ifbody,elsebody}|tree],ctx) do
    case has_def?(ctx,name) do
      true -> find_defns(ifbody++tree,ctx)
      false -> find_defns(elsebody++tree,ctx)
    end
  end
  defp find_defns([_other|tree],ctx) do
    find_defns(tree,ctx)
  end

  defp mark_keywords(tokens) do
    mark_keywords(tokens,[])
  end
  defp mark_keywords([{:"-",{_,1}}=dash,{:atom,loc,kw}|tokens],out)
  when kw in [:define,:ifdef,:ifndef,:"else",:endif,:undef,:include,:include_lib] do
    keyword = binary_to_atom(atom_to_binary(kw)<>"_keyword")
    mark_keywords(tokens, [{keyword,loc},dash|out])
  end
  defp mark_keywords([tok|tokens],out) do
    mark_keywords(tokens,[tok|out])
  end
  defp mark_keywords([],out) do
    Enum.reverse(out)
  end

  defrecordp :qc_ctx, [:defs, :files, :relative_dirs, :includes]

  ## defs dictionary:
  defp init_ctx() do
    qc_ctx( defs: HashDict.new(), files: [], relative_dirs: [], includes: [] )
  end
  defp init_ctx(module,file,incls) do
    defs = [{ {:MODULE,0},{[],[{:atom,{1,1},module}]} },
            { {:MODULE_STRING,0},{[],[{:string,{1,1},atom_to_list(module)}]} }]
    ctx = qc_ctx(init_ctx(),includes: incls)
    put_defs( push_file(ctx, file), defs )
  end

  defp push_file(qc_ctx( files: files,
                         relative_dirs: rels,
                         includes: incls )=ctx,file) do
    ctx=put_def(ctx,{:FILE,0},{[],[{:string,{1,1},file}]})
    dir = Path.dirname(file)
    new_incl = Path.expand("../include",dir)
    qc_ctx( ctx, files: [file|files], relative_dirs: [dir|rels], includes: [new_incl|incls] )
  end

  defp pop_file(qc_ctx( files: [_|files],
                        relative_dirs: [_|rels],
                        includes: [_|incls] )=ctx) do
    ctx =
      case files do
        [old_file|_] ->
          put_def(ctx,{:FILE,0},{[],[{:string,{1,1},old_file}]})
        [] ->
          ctx
      end
    qc_ctx( ctx, files: files, relative_dirs: rels, includes: incls )
  end

  defp get_paths(qc_ctx( files: [f|_], relative_dirs: [rel|_], includes: incls )) do
    {f,rel,incls}
  end

  defp get_def(qc_ctx( defs: defs ),{name,arity}) do
    all_arity = Dict.fetch!(defs,name)
    Dict.fetch!(all_arity,arity)
  end

  defp defs_list(qc_ctx(defs: defs)) do
    Dict.to_list(defs)
  end

  defp put_defs( ctx, defs ) when is_list(defs) do
    Enum.reduce(defs,ctx,fn({d,defn},subctx) -> put_def(subctx,d,defn) end)
  end

  defp put_def( qc_ctx( defs: defs )=ctx,{name,arity},defn) do
    all_arity =
      case Dict.get(defs,name) do
        nil -> HashDict.new()
        aa -> aa
      end
    qc_ctx(ctx, defs: Dict.put(defs,name,Dict.put(all_arity,arity,defn)))
  end

  defp has_def?(qc_ctx(defs: defs),name) do
    Dict.has_key?(defs,name)
  end

  defp rm_def(qc_ctx(defs: defs)=ctx,name) do
    qc_ctx(ctx, defs: Dict.delete(defs,name))
  end

end

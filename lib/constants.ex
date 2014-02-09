defmodule Quaff.Constants do
  defmacro include(header, options // []) do
    use_constants = options[:constants] || :all
    incl_type = case options[:include_lib] do
                 true -> :macro_include_lib
                 _ -> :macro_include
               end
    do_export = options[:export] || false
    const = Enum.map(get_constants(incl_type,header),
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
  defmacro include_lib(header, options // []) do
    quote do
      include(unquote(header),unquote(Keyword.put(options,:include_lib,true)))
    end
  end

  def normalize_const(a) when is_atom(a) do
    normalize_const(atom_to_binary(a))
  end
  def normalize_const(name) do
    c = String.first(name)
    normed_str =
      case String.upcase(c) do
        ^c -> "_"<>name
        _ -> name
      end
    binary_to_atom(normed_str)
  end

  def get_constants(header_file) do
    get_constants(:macro_include,header_file)
  end
  def get_constants(incl_type,header_file) do
    {:ok, tree} = read_header(incl_type,header_file)
    defs = find_defns(tree,HashDict.new())
    def_list = Dict.to_list(defs)
    Enum.flat_map(def_list,
                  fn({macro,all_arity}) ->
                      case Dict.get(all_arity,0) do
                        nil -> []
                        {[],defn} ->
                          case :erl_parse.parse_term(defn++[{:dot,0}]) do
                            {:ok, term} ->
                              [{macro,term}]
                            _ ->
                              []
                          end
                      end
                  end)
  end

  def read_header(header_file) do
    read_header(:macro_include,header_file)
  end
  def read_header(incl_type,header_file) do
    {:ok,realfile} = resolve_include(incl_type,header_file)
    {:ok,contents} = File.read(realfile)
    {:ok,contents} = String.to_char_list(contents)
    {:ok,h_toks,_} = :erl_scan.string(contents,{1,1})
    tokens = mark_keywords(h_toks)
    :aleppo_parser.parse(tokens)
  end

  def resolve_include(:macro_include_lib,file) do
    [app_name|file_path] = :filename.split(String.to_char_list!(file))
    case :code.lib_dir(list_to_atom(app_name)) do
      {:error, _} ->
        {:error, {:not_found,file}}
      app_lib ->
        {:ok,iolist_to_binary(:filename.join([app_lib|file_path]))}
    end
  end
  def resolve_include(:macro_include,file) do
    case :code.where_is_file(String.to_char_list!(file)) do
      :non_existing -> {:error, {:not_found,file}}
      filename -> {:ok, iolist_to_binary(filename)}
    end
  end

  def get_def(defs,{name,arity}) do
    all_arity = Dict.fetch!(defs,name)
    Dict.fetch!(all_arity,arity)
  end

  def put_def(defs,{name,arity},defn) do
    all_arity =
      case Dict.get(defs,name) do
        nil -> HashDict.new()
        aa -> aa
      end
    Dict.put(defs,name,Dict.put(all_arity,arity,defn))
  end

  def has_def?(defs,name) do
    Dict.has_key?(defs,name)
  end

  def rm_def(defs,name) do
    Dict.delete(defs,name)
  end

  def expand_nested(tokens,defs) do
    expand_nested(tokens,[],defs)
  end
  def expand_nested([],acc,_) do
    Enum.reverse(acc)
  end
  def expand_nested([{:macro,{_,_,name}}|tokens], acc, defs) do
    {[],def_toks} = get_def(defs,{name,0})
    expand_nested( tokens, Enum.reverse(def_toks) ++ acc, defs )
  end
  def expand_nested([{:macro,{_,_,name},args}|tokens], acc, defs) do
    {arg_names,def_toks} = get_def(defs,{name,length(args)})
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
    expand_nested(tokens,Enum.reverse(filled_in)++acc,defs)
  end
  def expand_nested([other|tokens],acc,defs) do
    expand_nested(tokens,[other|acc],defs)
  end

  def find_defns([],defs) do
    defs
  end
  def find_defns([{:macro_define,{_,_,name}}|tree],defs) do
    find_defns( tree, put_def(defs,{name,0},{[],true}) )
  end
  def find_defns([{:macro_define,{_,_,name},toks}|tree],defs) do
    expanded = expand_nested(toks,defs)
    find_defns( tree, put_def(defs,{name,0},{[],expanded}) )
  end
  def find_defns([{:macro_define,{_,_,name},args,toks}|tree],defs) do
    expanded = expand_nested(toks,defs)
    arg_names = Enum.map(args,
                         fn([{:var,_,var_name}]) ->
                              var_name
                          end)
    find_defns( tree, put_def(defs,{name,length(args)},{arg_names,expanded}) )
  end
  def find_defns([{:macro_undef,{_,_,name}}|tree],defs) do
    find_defns( tree, rm_def(defs,name) )
  end
  def find_defns([{incl_type,{:string,_,file}}|tree],defs)
  when incl_type == :macro_include or incl_type == :macro_include_lib do
    {:ok,subtree} = read_header(incl_type,file)
    find_defns(subtree++tree,defs)
  end
  def find_defns([{:macro_ifdef,x,ifbody}|tree],defs) do
    find_defns([{:macro_ifdef,x,ifbody,[]}|tree],defs)
  end
  def find_defns([{:macro_ifndef,x,ifbody}|tree],defs) do
    find_defns([{:macro_ifdef,x,[],ifbody}|tree],defs)
  end
  def find_defns([{:macro_ifndef,x,ifbody,elsebody}|tree],defs) do
    find_defns([{:macro_ifdef,x,elsebody,ifbody}|tree],defs)
  end
  def find_defns([{:macro_ifdef,{_,_,name},ifbody,elsebody}|tree],defs) do
    case has_def?(defs,name) do
      true -> find_defns(ifbody++tree,defs)
      false -> find_defns(elsebody++tree,defs)
    end
  end
  def find_defns([_other|tree],defs) do
    find_defns(tree,defs)
  end

  def mark_keywords(tokens) do
    mark_keywords(tokens,[])
  end
  def mark_keywords([{:"-",{_,1}}=dash,{:atom,loc,kw}|tokens],out)
  when kw in [:define,:ifdef,:ifndef,:"else",:endif,:undef,:include,:include_lib] do
    keyword = binary_to_atom(atom_to_binary(kw)<>"_keyword")
    mark_keywords(tokens, [{keyword,loc},dash|out])
  end
  def mark_keywords([tok|tokens],out) do
    mark_keywords(tokens,[tok|out])
  end
  def mark_keywords([],out) do
    Enum.reverse(out)
  end
end
 
defmodule Quaff.ConstantsCheck do
  require Quaff.Constants

  Quaff.Constants.include("foo.hrl", export: true)
end
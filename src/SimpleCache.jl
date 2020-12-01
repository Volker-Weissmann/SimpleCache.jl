module SimpleCache

import Serialization
using InteractiveUtils


if ! @isdefined macro_cache
    macro_cache = Dict()
end
# We need a data type that no method has a specialisation for. So we declare
# CacheFakeStruct. Don't write a function that takes this as an argument
struct CacheFakeStruct
end
function remove_certain_lines(src)
    ret = ""
    state = 0
    for line in split(src, "\n")
        if endswith(line, " Base.CoreLogging.Debug")
            state = 1
        end
        if state == 0
            ret *= line * "\n"
        end
        if endswith(line, "  Base.CoreLogging.nothing")
            state = 0
        end
    end
    return ret
end
function extract_arg_types(sig)
    str = string(sig)
    str = str[length("Tuple{")+1: end-1]
    str = join(split(str, ",")[2:end], ",")
    depth = 0
    splitpoints = [0]
    for i in 1:length(str)
        c = str[i]
        if c == ',' && depth == 0
            push!(splitpoints, i)
        elseif c == '{'
            depth += 1
        elseif c == '}'
            depth -= 1
        end
    end
    push!(splitpoints, length(str)+1)
    vals = []
    for i in 1:length(splitpoints)-1
        type = eval(Meta.parse(str[splitpoints[i]+1:splitpoints[i+1]-1]))
        if type == Any
            val = CacheFakeStruct()
        elseif type == Tuple
            val = (CacheFakeStruct(),CacheFakeStruct())
        else
            @debug str
            val = Array{type}(undef)[1]
        end
        push!(vals, val)
    end
    vals
end
function get_ast_of_meth(meth)
    funcname = meth.name
    sig = meth.sig
    type_examples = extract_arg_types(sig)
    inner_ast = @code_typed eval(funcname)(type_examples...)
    return inner_ast
end
function hash_function_recursive(already_visited, ast, is_typed::Bool)
    if typeof(ast) == Array{Core.CodeInfo,1}
        return 0
    end
    ret = hash(remove_certain_lines(string(ast)))
    if ret in already_visited
        return 0
    end
    push!(already_visited, ret) 
    if is_typed
        ast = ast[1]
    end
    for cmd in ast.code
        if typeof(cmd) in [Core.NewvarNode, Core.GotoNode, Core.SlotNumber]
            continue
        end
        if typeof(cmd) == GlobalRef
            if cmd.mod == Main
                ret = hash((ret, eval(cmd)))
            end
            continue
        end
        if startswith(string(typeof(cmd)), "Tuple{")
            for el in cmd
                @assert typeof(el) == Symbol
            end
            continue
        end

        if hasfield(typeof(cmd), :head) && cmd.head == :call && typeof(cmd.args[1]) == GlobalRef && cmd.args[1].mod == Main
            if length(cmd.args) == 1
                func = @which eval(cmd.args[1])()
                if is_typed
                    inner_ast = @code_typed(eval(cmd.args[1])())
                else
                    inner_ast = @code_lowered(eval(cmd.args[1])())
                end
            else
                func = @which eval(cmd.args[1])(cmd.args[2:end])
                if is_typed
                    inner_ast = @code_typed(eval(cmd.args[1])(cmd.args[2:end]))    
                else
                    inner_ast = @code_lowered(eval(cmd.args[1])(cmd.args[2:end]))
                end
            end
            if !(inner_ast in already_visited) && contains(string(func), "Main")
                ret = hash((ret, hash_function_recursive(already_visited, inner_ast, is_typed)))
            end
        end
        if hasfield(typeof(cmd), :args)
            if length(cmd.args) == 0
                continue
            end            
            if typeof(cmd.args[1]) == Core.MethodInstance
                if cmd.args[1].def.module != Main
                    continue
                end
                funcname = cmd.args[1].def
                inner_ast = get_ast_of_meth(funcname)
                ret = hash((ret, hash_function_recursive(already_visited, inner_ast, is_typed)))
            end
            for i in 1:length(cmd.args)
                arg = cmd.args[i]
                if typeof(arg) == GlobalRef && arg.mod == Main
                    ret = hash((ret, eval(arg)))
                end
            end
        end
    end
    return ret
end
macro cache_function(longname)
    cachedir = joinpath(ENV["HOME"], "julia_cache")
    func = Symbol(longname)
    @assert startswith(longname, "cached_")
    shortname = longname[length("cached_")+1:end]
    outer_func = Symbol(shortname)
    :(function $(esc(outer_func))(args...)
        depshash = hash((hash_function_recursive([], @code_typed($func(args...)), true), args ))
        fp = joinpath($cachedir, string(depshash))
        if haskey(macro_cache, depshash)
            ret = macro_cache[depshash]
        elseif isfile(fp)
            cache = Base.open(fp, "r")
            ret = Serialization.deserialize(cache)
            Base.close(cache)
            macro_cache[depshash] = ret
        else
            ret = $func(args...)
            cache = Base.open(fp, "w")
            Serialization.serialize(cache, ret)
            Base.close(cache)
            macro_cache[depshash] = ret
        end
        return ret
    end)
end
macro cached(func)
    inner_func = "cached_" * string(func.args[1].args[1])
    func.args[1].args[1] = esc(Symbol(inner_func))
    return :(:block, $func, @cache_function($inner_func))
end


end # module

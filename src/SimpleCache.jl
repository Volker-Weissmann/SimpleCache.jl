module SimpleCache
import Serialization
using InteractiveUtils

export set_cache_path, @cached

Simple_Cache_Path = joinpath(".", "julia_simple_cache")

if ! @isdefined macro_cache
    macro_cache = Dict()
end

# We need a data type that no method has a specialisation for. So we declare
# CacheFakeStruct. Don't write a function that takes this as an argument
struct CacheFakeStruct
end

"""
If you call this function before running @cached, then the cache will be written into `path`.
Otherwise, it defaults to `./julia_simple_cache`.
"""
function set_cache_path(path)
    global Simple_Cache_Path
    Simple_Cache_Path = path
end

function lowered_remove_certain_lines(src)
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

function typed_remove_certain_lines(src)
    ret = ""
    state = 0
    for line in split(src, "\n")
        if endswith(line, "  = Base.CoreLogging.Debug::Core.Compiler.Const(Debug, false)")
            state = 1
        end
        if state == 0
            ret *= line * "\n"
        end
        if contains(line, "  Base.CoreLogging.logging_error(")
            state = 0
        end
    end
    #Base.CoreLogging.Debug::Core.Compiler.Const(Debug, false)
    #  Base.CoreLogging.logging_error
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
    inner_ast = @code_typed Main.eval(funcname)(type_examples...)
    return inner_ast
end

function hash_function_recursive(already_visited, ast, is_typed::Bool)
    #@debug ast
    if typeof(ast) == Array{Core.CodeInfo,1}
        return 0
    end
    if is_typed
        ret = hash(typed_remove_certain_lines(string(ast)))
    else
        ret = hash(lowered_remove_certain_lines(string(ast)))
    end
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
            #@debug "GlobalRef:" cmd
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
            #@debug "call:" cmd.args[1]
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
            #@debug "args:" cmd.args
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

function cache_function(longname)
    func = Symbol(longname)
    @assert startswith(longname, "cached_")
    shortname = longname[length("cached_")+1:end]
    outer_func = Symbol(shortname)
    ret = :(function $(esc(outer_func))(args...)
        depshash = hash((hash_function_recursive([], @code_typed(Main.$func(args...)), true), args ))
        fp = joinpath($Simple_Cache_Path, string(depshash))
        if haskey(macro_cache, depshash)
            ret = macro_cache[depshash]
        elseif isfile(fp)
            cache = Base.open(fp, "r")
            ret = Serialization.deserialize(cache)
            Base.close(cache)
            macro_cache[depshash] = ret
        else
            ret = Main.$func(args...)
            cache = Base.open(fp, "w")
            Serialization.serialize(cache, ret)
            Base.close(cache)
            macro_cache[depshash] = ret
        end
        return ret
			end)
	ret
end

macro cached(func)
    if !isdir(Simple_Cache_Path)
        mkpath(Simple_Cache_Path)
        println("Created directory SimpleCache.Cache_Path == ", string(Simple_Cache_Path))
    end
    inner_func = "cached_" * string(func.args[1].args[1])
    func.args[1].args[1] = Symbol(inner_func)
	temp = cache_function(inner_func)
    return :(:block, $(esc(func)) , $temp)
end


end # module

# You cannot start or import this file directly, use runtest.jl instead
using InteractiveUtils
include("../src/SimpleCache.jl")

@noinline function multi(x::Int)
    println("printing stuff 1")
    @debug "debug macro 1"
    return VALUE_A
end

@noinline function multi(x)
    println("printing stuff 2")
    @debug "debug macro 2"
    return VALUE_B
end

@noinline function caller(x)
    multi(x)
    return 5
end

global glob = VALUE_C
@noinline function use_global()
    return glob
end

const constglob = VALUE_D
@noinline function use_const()
    return constglob
end

@noinline function ya_func(x)
    return VALUE_E
end

@noinline function pointer(x)
    if rand() > 0.5
        ptr = multi
    else
        ptr = ya_func
    end
    return ptr(x)
end

println(SimpleCache.hash_function_recursive([], @code_typed(caller(4)), true))
println(SimpleCache.hash_function_recursive([], @code_typed(caller(4.0)), true))
println(SimpleCache.hash_function_recursive([], @code_typed(use_global()), true))
println(SimpleCache.hash_function_recursive([], @code_typed(use_const()), true))
println(SimpleCache.hash_function_recursive([], @code_typed(pointer(4)), true))
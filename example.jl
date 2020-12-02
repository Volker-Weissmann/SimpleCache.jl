using SimpleCache

set_cache_path("test_cache") # Optional, defaults to "julia_simple_cache"

function depend(x)
	return x+1
end

@cached function heavy_calculation(x)
    println("doing heavy work work for x = ", x)
    sleep(2)
    return x * depend(x)
end

println(heavy_calculation(1))
println(heavy_calculation(2))
println(heavy_calculation(1))

# A simple caching system to improve your workflow

Normally, every time you run your script, *everything* gets calculated again,
even the parts of the script that did not change This package solves this waste
of calculation time, by using reflection to generate a dependency graph of your
source code:

Simply add `@cached` in front of a function name like in
`example.jl`:

```julia
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
```

Now, `heavy_calculation` will only run twice, (once for `x=1` and once for
`x=2`) instead of three times. If you restart Julia, `heavy_calculation` won't
run at all. Instead, `heavy_calculation(1)` will return a cached result.

If you change the source code of `heavy_calculation`, or `depend`, then
`heavy_calculation` will run again if you execute the program.

If you change the
source code of a function that is not used by `heavy_calculation`, then
`heavy_calculation` will *not* run again if you execute the program.

Note that the way that `SimpleCache.jl` uses reflection to see which source code is
relevant to a function is written in an extremely hacky way. Therefore, there
currently are dependendies that `SimpleCache.jl` won't be able to detect: Uses
of `eval` and conditional function pointer usuage.

Also note that `SimpleCache.jl` will never delete any cached data from disk.
You will have to manually delete it if your disk storage runs full.
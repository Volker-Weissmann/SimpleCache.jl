import SimpleCache
ENV["JULIA_DEBUG"] = Main;


"Run a Cmd object, returning the stdout & stderr contents plus the exit code"
function execute(cmd::Cmd)
  out = Pipe()
  err = Pipe()

  process = run(pipeline(ignorestatus(cmd), stdout=out, stderr=err))
  close(out.in)
  close(err.in)

  (
    stdout = String(read(out)), 
    stderr = String(read(err)),  
    code = process.exitcode
  )
end

# Which of the hashes SHOULD change when which value changes is encoded in
# dependency_graph
dependency_graph = Dict(
    "VALUE_A" => [1, 5],
    "VALUE_B" => [2],
    "VALUE_C" => [3],
    "VALUE_D" => [4],
    "VALUE_E" => [5],
)

Base.replace(s::String, oldnews::Pair...) = foldl(replace, oldnews, init=s)

# calc_hashes replaces VALUE_A and VALUE_B in original.jl according to replacedict, then runs this file and report the calculated hashes
function calc_hashes(prefix_newlines::Bool, replacedict)
    src = read("original.jl", String)
    if prefix_newlines
        src = "\n\n" * src
    end
    src = replace(src, replacedict...)
    write("generated.jl", src)
    output = execute(`julia generated.jl`)
    @assert output.code == 0

    ar = split(output.stdout, "\n")
    ar = [el for el in ar if el != ""]
    hashes = parse.(UInt64, ar)
    hashes
end

function gen_default_dict()
    default_dict = Dict()
    counter = 0
    for el in dependency_graph
        counter += 1
        default_dict[el[1]] = counter
    end
    default_dict
end

h1 = calc_hashes(false, gen_default_dict())
h2 = calc_hashes(false, gen_default_dict())
@assert(h1 == h2 , "Instable across restarts!")
h3 = calc_hashes(true, gen_default_dict())
@assert(h1 == h3 , "Instable againes linechanges!")

for el in dependency_graph
    dict = gen_default_dict()
    dict[el[1]] += 100
    hr = calc_hashes(false, dict)
    for i in 1:length(hr)
        if i in el[2]
            if i == 5 # The 5th test (function pointer(x)) is known broken
                continue
            end
            @assert(hr[i] != h1[i], string(i) * "-th Hash stayed identical, but should have changed when " * el[1] * " changed")
        else
            @assert(hr[i] == h1[i], string(i) * "-th Hash changed, but should have stayed identical when " * el[1] * " changed")
        end
    end
end
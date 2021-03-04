langs = {'c'}

function dependencies(profile)
    deps = {}
    if profile.build_type == 'debug' then
        deps.pkga = '>=1.0.0'
    end
    if profile.compilers.c.name == 'GCC' then
        deps.pkgc = '>=1.0.0'
    end
    return deps
end

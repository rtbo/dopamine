local dop = {}

function dop.Git(params)
    params.type = "source"
    params.method = "git"
    return params
end

function dop.Meson(params)
    params.type = "build"
    params.method = "meson"
    return params
end

return dop

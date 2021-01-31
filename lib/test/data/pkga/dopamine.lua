local dop = require('dop')

name = 'pkga'
version = '1.0.0'

function source()
    return '.'
end

function build(dirs, profile)
    local meson = dop.Meson:new(profile)

    local build = dop.path('..', '..', 'gen', 'pkga', 'build', profile.digest_hash)
    dop.mkdir {build, recurse = true}

    meson:setup{build_dir = build, install_dir = dirs.install}
    dop.from_dir(build, function()
        meson:compile()
        meson:install()
    end)
end

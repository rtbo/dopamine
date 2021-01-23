local dop = require('dop')

name = 'pkga'
version = '1.0.0'

function source()
    return '.'
end

function build(dirs, profile)
    local meson = dop.Meson:new(profile)

    dop.from_dir(dirs.src, function()
        local build = dop.path('build', profile.digest_hash)
        dop.mkdir {build, recurse = true}
        meson:setup{build_dir = build, install_dir = dirs.install}
        dop.from_dir(build, function()
            meson:compile()
            meson:install()
        end)
    end)
end

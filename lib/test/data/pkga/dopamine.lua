local dop = require('dop')

name = 'pkga'
version = '1.0.0'

function source()
    return '.'
end

function build(dirs, config)
    local profile = config.profile
    local meson = dop.Meson:new(profile)

    dop.mkdir {dirs.build, recurse = true}

    meson:setup{build_dir = dirs.build, install_dir = dirs.install}
    dop.from_dir(dirs.build, function()
        meson:compile()
        meson:install()
    end)

    return true
end

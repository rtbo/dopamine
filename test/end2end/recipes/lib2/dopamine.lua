return {
    name = 'lib2',
    version = '1.0.0',
    langs = {'c'},
    revision = '1',

    source = function()
        -- mimic a download to src/
        dop.mkdir('src')
        dop.copy('lib2.h', 'src')
        dop.copy('lib2.c', 'src')
        dop.copy('meson.build', 'src')
        return "."
    end,

    build = function(self, dirs, config)
        local profile = config.profile
        local meson = dop.Meson:new(profile)

        dop.mkdir {dirs.build, recurse = true}

        meson:setup{build_dir = dirs.build, install_dir = dirs.install}
        dop.from_dir(dirs.build, function()
            meson:compile()
            meson:install()
        end)

        return true
    end,
}

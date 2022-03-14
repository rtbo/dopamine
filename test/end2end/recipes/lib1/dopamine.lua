return {
    name = 'lib1',
    version = '1.0.0',
    langs = {'c'},
    revision = '1',

    -- called from the config directory
    build = function(self, src_dir, config)
        local meson = dop.Meson:new(config.profile)

        build_dir = dop.mkdir {"build", recurse = true}


        meson:setup{build_dir = dirs.build, install_dir = dirs.install}
        dop.from_dir(dirs.build, function()
            meson:compile()
            meson:install()
        end)

        return true
    end,
}

return {
    name = 'lib2',
    version = '1.0.0',
    langs = {'c'},
    revision = '1',

    build = function(self, dirs, config)
        local profile = config.profile
        local meson = dop.Meson:new(profile)

        build_dir = dop.mkdir {"build", recurse = true}

        meson:setup{build_dir = build_dir, src_dir = dirs.src}
        dop.from_dir("build", function()
            meson:compile()
            meson:install()
        end)

        return true
    end,
}

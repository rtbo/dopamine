return {
    name = 'lib1',
    version = '1.0.0',
    langs = {'c'},
    revision = '1',

    -- called from the config directory
    build = function(self, dirs, config)
        local meson = dop.Meson:new(config.profile)

        meson:setup{build_dir = '.', src_dir = dirs.src, install_dir = dirs.install}
        meson:compile()
        meson:install()
    end,
}

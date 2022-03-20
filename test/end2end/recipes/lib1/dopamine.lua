return {
    name = 'lib1',
    version = '1.0.0',
    langs = {'c'},
    revision = '1',

    -- called from the config directory
    build = function(self, dirs, config)
        local meson = dop.Meson:new(config.profile)

        build_dir = dop.mkdir {"build", recurse = true}

        meson:setup{build_dir = build_dir, src_dir = dirs.src}
        dop.from_dir(build_dir, function() meson:compile() end)

        return true
    end,
}

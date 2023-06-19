name = 'app2'
version = '1.0.0'
tools = { 'dc' }

dependencies = {
    pkgb = '>=1.0.0',
}

function build(dirs, config, deps)
    local profile = config.profile
    local meson = dop.Meson:new(profile)

    local env = {
        PKG_CONFIG_PATH = dop.path(
            deps['pkgb'].install_dir,
            'lib',
            'pkgconfig'
        ),
    }

    meson:setup(
        { build_dir = '.', src_dir = dirs.src, install_dir = dirs.install },
        env
    )
    meson:compile()
    meson:install()
end


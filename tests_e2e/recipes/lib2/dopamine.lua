name = 'lib2'
version = '1.0.0'
tools = { 'cc' }

dependencies = {
    pkga = '>=1.0.0',
}

include = {
    'lib2.c',
    'lib2.h',
    'meson.build',
}

function build(dirs, config, dep_infos)
    local profile = config.profile
    local meson = dop.Meson:new(profile)
    local pkga = dep_infos.dop.pkga;

    local env = {
        PKG_CONFIG_PATH = dop.path(
            pkga.install_dir,
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

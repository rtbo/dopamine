name = 'options-dep'
version = '1.0.0'
description = 'a test library with options'
upstream_url = 'https://github.com/rtbo/dopamine'
license = 'MIT'
tools = { 'dc' }

dependencies = {
    options = {
        version = '1.0.0',
    },
}

function build(dirs, config, dep_infos)
    local meson = dop.Meson:new(config.profile)
    meson:setup({
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
    }, {
        PKG_CONFIG_PATH = dop.pkg_config_path(dep_infos),
    })
    meson:compile()
    meson:install()
end

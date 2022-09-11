name = 'dub-dep'
version = '1.0.0'
tools = { 'dc' }

dependencies = {
    urld = { version = '~>2.1.1', dub = true },
}

function build(dirs, config, dep_infos)
    local meson = dop.Meson:new(config.profile)

    meson:setup {
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        pkg_config_path = dop.pkg_config_path(dep_infos),
    }
    meson:compile()
    meson:install()
end

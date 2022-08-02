name = 'xlsx-app'
version = '1.0.0'
langs = {'d'}

dependencies = {
    ['xlsxreader'] = { version = '~>2.1', dub = true }
}

function build(dirs, config, dep_infos)
    local meson = dop.Meson:new(config.profile)

    meson:setup({
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        pkg_config_path = dop.pkg_config_path(dep_infos)
    })
    meson:compile()
    meson:install()
end

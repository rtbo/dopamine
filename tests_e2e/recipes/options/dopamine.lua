name = 'options'
version = '1.0.0'
description = 'a test library with options'
upstream_url = 'https://github.com/rtbo/dopamine'
license = 'MIT'
tools = { 'dc' }

options = {
    lib1 = {
        type = 'boolean',
        default = true,
        description = 'Enable lib1 module',
    },
    lib2 = false,
}

function build(dirs, config)
    local meson = dop.Meson:new(config.profile)
    meson:setup {
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = {
            enable_lib1 = config.options.lib1,
            enable_lib2 = config.options.lib2,
        },
    }
    meson:compile()
    meson:install()
end

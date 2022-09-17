name = 'options'
version = '1.0.0'
description = 'a test library with options'
upstream_url = 'https://github.com/rtbo/dopamine'
license = 'MIT'
tools = { 'dc' }

options = {
    a = true,
    b = false,
}

function build(dirs, config)
    local meson = dop.Meson:new(config.profile)
    meson:setup {
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = {
            feature_a = config.options.a,
            feature_b = config.options.b,
        },
    }
    meson:compile()
    meson:install()
end

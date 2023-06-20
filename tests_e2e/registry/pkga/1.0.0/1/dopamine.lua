name = 'pkga'
version = '1.0.0'
tools = { 'cc' }

function build(dirs, config)
    local meson = dop.Meson:new(config.profile)
    meson:setup({
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = {
            default_library = 'static'
        }
    })
    meson:compile()
    meson:install()
end

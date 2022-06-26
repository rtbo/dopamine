name = 'pkga'
version = '1.0.0'
langs = {'c'}
revision = '1'

function build(dirs, config)
    local profile = config.profile
    local meson = dop.Meson:new(profile)

    meson:setup{build_dir = '.', src_dir = dirs.src, install_dir = dirs.install}
    meson:compile()
    meson:install()
end

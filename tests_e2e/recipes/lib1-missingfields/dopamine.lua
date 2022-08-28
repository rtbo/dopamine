name = 'lib1'
version = '1.0.0'
tools = {'cc'}

include = {
    'lib1.c',
    'lib1.h',
    'meson.build',
}

-- called from the config directory
function build (dirs, config)
    local meson = dop.Meson:new(config.profile)

    meson:setup{build_dir = '.', src_dir = dirs.src, install_dir = dirs.install}
    meson:compile()
    meson:install()
end

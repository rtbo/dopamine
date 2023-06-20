name = 'pkgb'
version = '2.0.0'
description = 'Package B'
tools = { 'dc' }

dependencies = {
    pkga = '>=2.0.0',
}

function build(dirs, config, dep_infos)
    local meson = dop.Meson:new(config.profile)
    meson:setup({
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = {
            default_library = 'static'
        }
    }, {
        PKG_CONFIG_PATH = dop.pkg_config_path(dep_infos),
    })
    meson:compile()
    meson:install()

    local pc = dop.PkgConfFile:new {
        vars = {
            prefix = dirs.install,
            includedir = '${prefix}/include',
            libdir = '${prefix}/lib',
        },
        name = name,
        version = version,
        description = description,
        cflags = '-I${includedir}',
        libs = '-L${libdir} -lpkgb',
        requires = { 'pkga >= 2.0.0' }
    }
    if dop.windows then
        pc:translate_msvc()
    end
    pc:write(dop.path(dirs.install, 'lib', 'pkgconfig', 'pkgb.pc'))

    local install = dop.installer(dirs.src, dirs.install)
    install.file('pkgb.d', dop.path('include'))
end

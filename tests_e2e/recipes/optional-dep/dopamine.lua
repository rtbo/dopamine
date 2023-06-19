name = 'optional-dep'
version = '1.0.0'
description = 'a package with dependency depending on options'
upstream_url = 'https://github.com/rtbo/dopamine'
license = 'MIT'
-- FIXME: cc here only because of dependencies, should not be needed
tools = { 'cc', 'dc' }

options = {
    pkgb = {
        type = 'boolean',
        default = false,
        description = 'Enable pkgb functionality',
    },
}

function dependencies(config)
    local deps = {}
    if (config.options.pkgb) then
        deps.pkgb = '>=1.0.0'
    end
    return deps
end

function build(dirs, config, dep_infos)
    local meson = dop.Meson:new(config.profile)
    meson:setup({
        build_dir = '.',
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = {
            enable_pkgb = config.options.pkgb
        }
    }, {
        PKG_CONFIG_PATH = dop.pkg_config_path(dep_infos),
    })
    meson:compile()
    meson:install()
end

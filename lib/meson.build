subdir('src/dopamine')

dop_src = files([
    'src/arsd/terminal.d',

    'src/bindbc/loader/package.d',
    'src/bindbc/loader/sharedlib.d',
    'src/bindbc/loader/system.d',
    'src/bindbc/lua/config.d',
    'src/bindbc/lua/package.d',
    'src/bindbc/lua/v53/binddynamic.d',
    'src/bindbc/lua/v53/bindstatic.d',
    'src/bindbc/lua/v53/package.d',
    'src/bindbc/lua/v53/types.d',

    'src/dopamine/ini.d',
    'src/dopamine/log.d',
    'src/dopamine/msvc.d',
    'src/dopamine/profile.d',
    'src/dopamine/semver.d',
    'src/dopamine/util.d',
])

dop_inc = include_directories('src')
dop_deps = [ lua_dep ]

dop_lib = library('dopamine', dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_module_versions: lua_d_versions,
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: [dop_lib],
)

subdir('src/dopamine')

dop_src = files([
    'src/bindbc/loader/package.d',
    'src/bindbc/loader/sharedlib.d',
    'src/bindbc/loader/system.d',
    'src/bindbc/lua/config.d',
    'src/bindbc/lua/package.d',
    'src/bindbc/lua/v53/binddynamic.d',
    'src/bindbc/lua/v53/bindstatic.d',
    'src/bindbc/lua/v53/package.d',
    'src/bindbc/lua/v53/types.d',

    'src/dopamine/archive.d',
    'src/dopamine/build_id.d',
    'src/dopamine/cache.d',
    'src/dopamine/dep/dag.d',
    'src/dopamine/dep/lock.d',
    'src/dopamine/dep/service.d',
    'src/dopamine/dep/spec.d',
    'src/dopamine/ini.d',
    'src/dopamine/log.d',
    'src/dopamine/login.d',
    'src/dopamine/lua/lib.d',
    'src/dopamine/lua/package.d',
    'src/dopamine/lua/profile.d',
    'src/dopamine/lua/util.d',
    'src/dopamine/msvc.d',
    'src/dopamine/paths.d',
    'src/dopamine/profile.d',
    'src/dopamine/recipe.d',
    'src/dopamine/registry.d',
    'src/dopamine/util.d',
])

lua_d_versions = ['LUA_53', 'BindBC_Static']

dop_inc = include_directories('src')
dop_deps = [ lua_dep, dop_common_dep, vibed_data_dep ]
dop_imp = include_directories('src/dopamine/lua')

dop_lib = library('dopamine', dop_conf, dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_module_versions: lua_d_versions,
    d_import_dirs: dop_imp,
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: [dop_lib],
)

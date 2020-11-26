
dop_src = [
    'src/dopamine/dependency.d',
    'src/dopamine/pack.d',
    'src/dopamine/profile.d',
    'src/dopamine/recipe.d',
    'src/dopamine/source.d',
    'src/dopamine/util.d',
]

dop_inc = include_directories('src')
dop_deps = [ dop_lua_dep ]

dop_lib = library('dopamine', dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_import_dirs: include_directories('lua'),
    d_module_versions: ['LUA_53', 'LUA_53_DYNAMIC'],
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: dop_lib,
)

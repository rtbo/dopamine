
dop_src = [
    'src/dopamine/build.d',
    'src/dopamine/paths.d',
    'src/dopamine/profile.d',
    'src/dopamine/recipe.d',
    'src/dopamine/source.d',
    'src/dopamine/util.d',
]

dop_inc = include_directories('src')
dop_deps = [ dop_lua_dep, dini_dep ]

dop_lib = library('dopamine', dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_import_dirs: include_directories('lua'),
    d_module_versions: lua_d_versions,
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: dop_lib,
)

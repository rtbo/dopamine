dop_client_src = [
    'src/dopamine/client/app.d',
    'src/dopamine/client/build.d',
    'src/dopamine/client/cache.d',
    'src/dopamine/client/depinstall.d',
    'src/dopamine/client/deplock.d',
    'src/dopamine/client/login.d',
    'src/dopamine/client/pack.d',
    'src/dopamine/client/profile.d',
    'src/dopamine/client/publish.d',
    'src/dopamine/client/recipe.d',
    'src/dopamine/client/source.d',
]

dop_client_inc = include_directories('src')

dop_client_exe = executable('dop', dop_client_src,
    install: true,
    include_directories: dop_client_inc,
    dependencies: dop_dep,
    d_module_versions: lua_d_versions,
)

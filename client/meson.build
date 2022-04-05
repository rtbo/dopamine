dop_client_src = files([
    'src/dopamine/client/app.d',
    'src/dopamine/client/build.d',
    'src/dopamine/client/login.d',
    'src/dopamine/client/pack.d',
    'src/dopamine/client/profile.d',
    'src/dopamine/client/resolve.d',
    'src/dopamine/client/source.d',
    'src/dopamine/client/utils.d',
])

dop_client_inc = include_directories('src')

dop_client_exe = executable('dop', dop_client_src,
    install: true,
    include_directories: dop_client_inc,
    dependencies: dop_dep,
    d_module_versions: lua_d_versions + ['DopClientMain'],
)

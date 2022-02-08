dop_client_src = [
    'src/dopamine/client/app.d',
    'src/dopamine/client/login.d',
]

dop_client_inc = include_directories('src')

dop_client_exe = executable('dop', dop_client_src,
    install: true,
    include_directories: dop_client_inc,
    dependencies: dop_dep,
    d_module_versions: lua_d_versions,
)

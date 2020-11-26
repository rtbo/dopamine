dop_client_src = [
    'src/dopamine/client/app.d',
    'src/dopamine/client/build.d',
]

dop_client_inc = include_directories('src')

dop_client_exe = executable('dop', dop_client_src,
    install: true,
    include_directories: dop_client_inc,
    dependencies: dop_dep,
    d_module_versions: ['LUA_53', 'LUA_53_DYNAMIC'],
)


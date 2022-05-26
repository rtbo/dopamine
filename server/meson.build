
dop_server_src = files([
    'src/dopamine/c/libpq/bindings.d',
    'src/dopamine/c/libpq/package.d',
    'src/dopamine/c/libpq/types.d',

    'src/dopamine/server/main.d',
])

dop_server_inc = include_directories('src')

dop_server_exe = executable('dop-server', dop_server_src,
    install: true,
    include_directories: dop_server_inc,
    dependencies: [vibed_http_dep, dop_common_dep, libpq_dep],
)

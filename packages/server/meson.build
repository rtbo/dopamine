
dop_server_src = files([
    'src/dopamine/server/v1/package.d',
    'src/dopamine/server/v1/recipes.d',

    'src/dopamine/server/app.d',
    'src/dopamine/server/auth.d',
    'src/dopamine/server/config.d',
    'src/dopamine/server/db.d',
    'src/dopamine/server/utils.d',
])
dop_server_inc = include_directories('src')

dop_server_exe = executable('dop-server', dop_server_src,
    install: true,
    include_directories: dop_server_inc,
    dependencies: [vibed_http_dep, squiz_dep, crypto_dep, cors_dep, jwt_dep, pgd_dep, dop_common_dep],
    d_module_versions: ['DopServerMain'],
)


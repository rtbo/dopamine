
dop_server_common_src = files([
    'src/dopamine/c/libpq/bindings.d',
    'src/dopamine/c/libpq/defs.d',
    'src/dopamine/c/libpq/package.d',

    'src/dopamine/server/config.d',
    'src/dopamine/server/db.d',
])

dop_server_src = dop_server_common_src + files([
    'src/dopamine/server/app.d',
])

dop_admin_src = dop_server_common_src + files([
    'src/dopamine/admin/app.d',
])

dop_server_inc = include_directories('src')

dop_server_exe = executable('dop-server', dop_server_src,
    install: true,
    include_directories: dop_server_inc,
    dependencies: [vibed_http_dep, libpq_dep, dop_common_dep],
    d_module_versions: ['DopServerMain'],
)

dop_admin_exe = executable('dop-admin', dop_admin_src,
    install: true,
    include_directories: dop_server_inc,
    dependencies: [vibed_http_dep, libpq_dep, dop_common_dep],
    d_module_versions: ['DopAdminMain', 'VibeDisableCommandLineParsing'],
    d_import_dirs: include_directories('migrations'),
)

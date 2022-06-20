dop_ut_src = dop_common_src + dop_src + dop_client_src + dop_server_src + dop_admin_src + pgd_src + jwt_src + files([
    'test/main.d',
    'test/util.d',
    'test/lua/lib.d',
    'test/lua/ut.d',
    'test/silly.d',
])

dop_ut_imp = [dop_imp, dop_admin_imp, include_directories('test/data')]
dop_ut_inc = [dop_common_inc, dop_inc, dop_client_inc, pgd_inc, jwt_inc, dop_admin_inc, dop_server_inc, include_directories('.')]

# all_mods defined in test
subdir('test')

dop_ut_exe = executable('unit-tests', all_mods, dop_ut_src,
    install: false,
    include_directories: dop_ut_inc,
    dependencies: [ut_assertions_dep, vibed_http_dep, libpq_dep, squiz_dep, dop_dep],
    d_import_dirs: dop_ut_imp,
    d_module_versions: lua_d_versions,
    d_unittest: true,
)

test('all unit tests', dop_ut_exe,
    args: ['--threads', '1'],
    suite: 'unit',
    is_parallel: false,
)

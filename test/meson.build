dop_test_src = dop_src + dop_client_src + files([
    'unit/test/main.d',
    'unit/test/silly.d',
    'unit/test/util.d',
    'unit/test/lua/lib.d',
    'unit/test/lua/ut.d',
])

dop_test_imp = [dop_imp, include_directories('unit/test/data')]
dop_test_inc = [dop_inc, dop_client_inc, include_directories('unit')]

# all_mods defined in test
subdir('unit/test')
dop_test_src += all_mods

dop_test_exe = executable('unittests', dop_test_src,
    install: false,
    include_directories: dop_test_inc,
    dependencies: dop_deps,
    d_import_dirs: dop_test_imp,
    d_module_versions: lua_d_versions,
    d_unittest: true,
)

test('Dopamine unit tests', dop_test_exe)

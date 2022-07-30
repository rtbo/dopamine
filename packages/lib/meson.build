subdir('src/dopamine')

dop_src = files([
    'src/dopamine/c/lua/bindings.d',
    'src/dopamine/c/lua/defs.d',
    'src/dopamine/c/lua/macros.d',
    'src/dopamine/c/lua/package.d',

    'src/dopamine/build_id.d',
    'src/dopamine/cache.d',
    'src/dopamine/dep/build.d',
    'src/dopamine/dep/dag.d',
    'src/dopamine/dep/dub.d',
    'src/dopamine/dep/lock.d',
    'src/dopamine/dep/service.d',
    'src/dopamine/dep/spec.d',
    'src/dopamine/ini.d',
    'src/dopamine/log.d',
    'src/dopamine/login.d',
    'src/dopamine/lua/lib.d',
    'src/dopamine/lua/profile.d',
    'src/dopamine/lua/util.d',
    'src/dopamine/msvc.d',
    'src/dopamine/paths.d',
    'src/dopamine/profile.d',
    'src/dopamine/recipe/dir.d',
    'src/dopamine/recipe/dop.d',
    'src/dopamine/recipe/dub.d',
    'src/dopamine/recipe/package.d',
    'src/dopamine/registry.d',
    'src/dopamine/util.d',
])

lua_d_versions = ['LUA_53', 'BindBC_Static']

dop_inc = include_directories('src')
dop_deps = [ lua_dep, dop_common_dep, jwt_dep, squiz_dep, vibed_data_dep, dub_dep ]
dop_imp = include_directories('src/dopamine/lua')

dop_lib = library('dopamine', dop_conf, dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_module_versions: lua_d_versions,
    d_import_dirs: dop_imp,
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: [dop_lib],
    sources: dop_conf,
)

if get_option('enable_test')
    dop_test_src = dop_src + files([
        'test/main.d',
        'test/util.d',
        'test/lua/lib.d',
        'test/lua/ut.d',
    ])

    dop_test_imp = [dop_imp, include_directories('test/data')]

    dop_stupid = custom_target('dop_stupid',
        capture: true,
        output: 'stupid.d',
        input: dop_test_src,
        command: [
            stupid_gen_exe, '@INPUT@',
        ],
    )

    dop_test_exe = executable('dop-dop-test', dop_stupid, dop_test_src,
        d_unittest: true,
        d_import_dirs: dop_test_imp,
        dependencies: [dop_deps, ut_assertions_dep],
        include_directories: include_directories('.', 'src'),
    )

    test('dop library unit tests', dop_test_exe,
        suite: 'unit',
    )
endif
dop_client_src = files([
    'src/dopamine/client/app.d',
    'src/dopamine/client/build.d',
    'src/dopamine/client/login.d',
    'src/dopamine/client/profile.d',
    'src/dopamine/client/publish.d',
    'src/dopamine/client/resolve.d',
    'src/dopamine/client/revision.d',
    'src/dopamine/client/search.d',
    'src/dopamine/client/source.d',
    'src/dopamine/client/stage.d',
    'src/dopamine/client/utils.d',
])

dop_client_inc = include_directories('src')

dop_client_exe = executable('dop', dop_client_src,
    install: get_option('enable_client'),
    include_directories: dop_client_inc,
    dependencies: dop_dep,
    d_module_versions: lua_d_versions + ['DopClientMain'],
)

if get_option('enable_test')

    dop_client_test_src = files([
        'src/dopamine/client/profile.d',
        'src/dopamine/client/utils.d',
    ])

    client_stupid = custom_target('client_stupid',
        capture: true,
        output: 'stupid.d',
        input: dop_client_test_src,
        command: [
            stupid_gen_exe, '@INPUT@',
        ],
    )

    dop_client_test_exe = executable('dop-client-test', client_stupid, dop_client_test_src,
        d_unittest: true,
        include_directories: include_directories('.', 'src'),
        dependencies: dop_dep,
    )

    test('client unit tests', dop_client_test_exe,
        suite: 'unit',
    )

endif

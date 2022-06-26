jwt_src = files([
    'src/jwt.d'
])

jwt_deps = [vibed_data_dep]

jwt_inc = include_directories('src')

jwt_lib = library('jwt', jwt_src,
    dependencies: jwt_deps,
)

jwt_dep = declare_dependency(
    link_with: jwt_lib,
    dependencies: jwt_deps,
    include_directories: jwt_inc,
)

if get_option('enable_test')
    jwt_test_src = files([
        'src/jwt.d',
    ])

    jwt_stupid = custom_target('jwt_stupid',
        capture: true,
        output: 'stupid.d',
        input: jwt_test_src,
        command: [
            stupid_gen_exe, '@INPUT@',
        ],
    )

    jwt_test_exe = executable('dop-jwt-test', jwt_stupid, jwt_test_src,
        d_unittest: true,
        dependencies: jwt_deps,
        include_directories: include_directories('.', 'src'),
    )

    test('jwt unit tests', jwt_test_exe,
        suite: 'unit',
    )
endif
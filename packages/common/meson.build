dop_common_src = files([
    'src/dopamine/api/attrs.d',
    'src/dopamine/api/v1.d',

    'src/dopamine/cache_dirs.d',
    'src/dopamine/semver.d',
])

dop_common_inc = include_directories('src')
dop_common_deps = [vibed_data_dep]

dop_common_lib = library('dop-common', dop_common_src,
    install: true,
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
)

dop_common_dep = declare_dependency(
    link_with: [dop_common_lib],
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
)

if get_option('enable_test')
    dop_common_test_src = files([
        'src/dopamine/semver.d',
    ])

    common_stupid = custom_target('common_stupid',
        capture: true,
        output: 'stupid.d',
        input: dop_common_test_src,
        command: [
            stupid_gen_exe, '@INPUT@',
        ],
    )

    dop_common_test_exe = executable('dop-common-test', common_stupid, dop_common_test_src,
        d_unittest: true,
        include_directories: include_directories('.', 'src'),
    )

    test('common unit tests', dop_common_test_exe,
        suite: 'unit',
    )
endif

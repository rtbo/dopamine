
pgd_src = files([
    'src/pgd/libpq/bindings.d',
    'src/pgd/libpq/defs.d',
    'src/pgd/libpq/package.d',

    'src/pgd/conn.d',
    'src/pgd/connstring.d',
    'src/pgd/conv/nullable.d',
    'src/pgd/conv/package.d',
    'src/pgd/conv/time.d',
    'src/pgd/maybe.d',
    'src/pgd/param.d',
    'src/pgd/result.d',
])

pgd_inc = include_directories('src')

pgd_lib = static_library('pgd', pgd_src,
    install: false,
    include_directories: pgd_inc,
)

pgd_dep = declare_dependency(
    link_with: pgd_lib,
    dependencies: libpq_dep,
    include_directories: pgd_inc,
)

if get_option('enable_test')
    pgd_test_src = files([
        'src/pgd/libpq/defs.d',
        'src/pgd/conv/nullable.d',
        'src/pgd/conv/package.d',
        'src/pgd/conv/test.d',
        'src/pgd/conv/time.d',
        'src/pgd/conn.d',
        'src/pgd/connstring.d',
        'src/pgd/maybe.d',
        'src/pgd/param.d',
        'src/pgd/result.d',
        'src/pgd/test.d',
    ])

    pgd_stupid = custom_target('pgd_stupid',
        capture: true,
        output: 'stupid.d',
        input: pgd_test_src,
        command: [
            stupid_gen_exe, '@INPUT@',
        ],
    )

    pgd_test_exe = executable('dop-pgd-test', pgd_stupid, pgd_test_src,
        d_unittest: true,
        dependencies: [libpq_dep, ut_assertions_dep],
        include_directories: include_directories('.', 'src'),
    )

    test('pgd unit tests', pgd_test_exe,
        suite: 'unit',
    )
endif
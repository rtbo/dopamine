
e2e_driver_src = files([
    'e2e_assert.d',
    'e2e_main.d',
    'e2e_registry.d',
    'e2e_sandbox.d',
    'e2e_test.d',
    'e2e_utils.d',
])

e2e_driver_exe = executable('e2e-driver', e2e_driver_src,
    install: false,
    dependencies: [vibed_http_dep, jwt_dep],
    d_module_versions: dop_registry_storage_versions,
)

e2e_tests = [
    'profile',
    'profile-describe',
    'profile-discover',

    'resolve-notarecipe',
    'resolve-light-cache',
    'resolve-light-highest',
    'resolve-lib2-cache',

    'source-notarecipe',
    'source-in-tree',
    'source-zlib',

    'build-lib1',
    'build-lib2',
    'build-zlib-posix',
    'build-zlib-win',
    'build-dublib',
    'build-xlsx-app',

    'dub-dep',

    'stage-lib2',

    'publish-lib1',
    'publish-missingfields',

    'search',

    'options',
    'options-dep',
    'options-dep2',

    'warning',
]

foreach e2e_test : e2e_tests

    test(e2e_test, e2e_driver_exe,
        args: [
            '--client-exe=' + dop_client_exe.full_path(),
            '--registry-exe=' + dop_registry_exe.full_path(),
            '--admin-exe=' + dop_admin_exe.full_path(),
            files('tests/' + e2e_test + '.test'),
        ],
        suite: 'e2e',
        timeout: 120,
    )

endforeach

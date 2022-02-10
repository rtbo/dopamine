
e2e_driver_exe = executable('e2e-driver', 'e2e_driver.d',
    install: false,
)

e2e_env = [
    'DOP='+dop_client_exe.full_path(),
]

e2e_tests = [
    'profile',
    'profile-describe',
]

foreach e2e_test : e2e_tests

    test(e2e_test, e2e_driver_exe,
        env: e2e_env,
        args: [files(e2e_test + '.test')],
        suite: 'e2e',
    )

endforeach

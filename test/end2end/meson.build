
e2e_driver_exe = executable('e2e-driver', 'e2e_driver.d',
    install: false,
)

e2e_env = [
    'DOP='+dop_client_exe.full_path()
]

test('read-profiles', e2e_driver_exe,
    env: e2e_env,
    args: [files('read-profiles.test')],
    suite: 'e2e',
)

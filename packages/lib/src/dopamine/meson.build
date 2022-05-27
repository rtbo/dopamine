
dop_conf = custom_target('conf_di',
    output: 'conf.di',
    input: 'conf.di.in',
    command: [config_gen, '--input', '@INPUT@', '--output', '@OUTPUT@'],
    install: true,
    install_dir: '.',
)

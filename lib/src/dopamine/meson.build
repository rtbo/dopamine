
conf_data = configuration_data()
conf_data.set('VERSION', meson.project_version())
configure_file(
    input: 'conf.di.in',
    output: 'conf.di',
    configuration: conf_data,
)

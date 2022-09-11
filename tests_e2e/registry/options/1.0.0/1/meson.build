project('options', ['d'],
    version: '1.0.0',
)

d_versions = []
if get_option('feature_a')
    d_versions += 'FeatureA'
endif
if get_option('feature_b')
    d_versions += 'FeatureB'
endif

options_lib = static_library('options', 'options.d',
    install: true,
    d_module_versions: d_versions,
)

pkgc = import('pkgconfig')
pkgc.generate(
    name: 'options',
    libraries: options_lib,
    subdirs: 'd/options',
    version: meson.project_version(),
    description: 'A D project with options',
    d_module_versions: d_versions,
)
install_headers('options.d', subdir: 'd/options')

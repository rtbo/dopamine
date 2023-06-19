project('optional-dep', ['d'],
    version: '1.0.0',
)

deps = []
versions = []

if get_option('enable_pkgb')
    deps += dependency('pkgb', method: 'pkg-config')
    versions += ['Have_pkgb']
endif

app = executable('optional-dep', 'app.d',
    install: true,
    dependencies: deps,
    d_module_versions: versions,
)

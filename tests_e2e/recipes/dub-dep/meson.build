project('dub-dep', ['d'], version: '1.0.0')

urld_dep = dependency('urld', method: 'pkg-config')

app = executable('app', 'app.d',
    install: true,
    dependencies: [urld_dep]
)

project('dub-dep', ['d'], version: '1.0.0')

urld_dep = dependency('urld', method: 'pkg-config')

app = executable('app', 'app.d',
    dependencies: [urld_dep]
)

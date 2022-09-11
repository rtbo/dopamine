project('options-dep', ['d'],
    version: '1.0.0',
)

options_dep = dependency('options', method: 'pkg-config')

app = executable('options-dep', 'app.d',
    install: true,
    dependencies: options_dep,
)

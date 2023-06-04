project('dub-dep', ['d'], version: '1.0.0')

vibe_http_dep = dependency('vibe-d_http', method: 'pkg-config')

app = executable('app', 'app.d',
    install: true,
    dependencies: [vibe_http_dep]
)

cors_src = files([
    'src/cors_vibe.d'
])

cors_deps = [vibed_http_dep]

cors_inc = include_directories('src')

cors_lib = library('cors', cors_src,
    dependencies: cors_deps,
)

cors_dep = declare_dependency(
    link_with: cors_lib,
    dependencies: cors_deps,
    include_directories: cors_inc,
)

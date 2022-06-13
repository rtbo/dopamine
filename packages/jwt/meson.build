jwt_src = files([
    'src/jwt.d'
])

jwt_deps = [vibed_data_dep]

jwt_inc = include_directories('src')

jwt_lib = library('jwt', jwt_src,
    dependencies: jwt_deps,
)

jwt_dep = declare_dependency(
    link_with: jwt_lib,
    dependencies: jwt_deps,
    include_directories: jwt_inc,
)

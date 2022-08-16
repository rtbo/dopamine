dop_api_src = files([
    'src/dopamine/api/attrs.d',
    'src/dopamine/api/auth.d',
    'src/dopamine/api/v1.d',
])

dop_api_inc = include_directories('src')
dop_api_deps = [vibed_data_dep]

dop_api_lib = library('dop-api', dop_api_src,
    install: true,
    include_directories: dop_api_inc,
    dependencies: dop_api_deps,
)

dop_api_dep = declare_dependency(
    link_with: [dop_api_lib],
    include_directories: dop_api_inc,
    dependencies: dop_api_deps,
)

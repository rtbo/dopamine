dop_common_src = files([
    'src/dopamine/api/attrs.d',
    'src/dopamine/api/auth.d',
    'src/dopamine/api/v1.d',
])

dop_common_inc = include_directories('src')
dop_common_deps = [vibed_data_dep]

dop_common_lib = library('dop-common', dop_common_src,
    install: true,
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
)

dop_common_dep = declare_dependency(
    link_with: [dop_common_lib],
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
)

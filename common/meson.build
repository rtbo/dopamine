dop_common_src = files([
    'src/dopamine/api/attrs.d',
    'src/dopamine/api/v1.d',

    'src/dopamine/cache_dirs.d',
    'src/dopamine/semver.d',
])

dop_common_inc = include_directories('src')
dop_common_deps = vibed_data_deps

dop_common_lib = library('dopamine', dop_common_src,
    install: true,
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
)

dop_common_dep = declare_dependency(
    include_directories: dop_common_inc,
    dependencies: dop_common_deps,
    link_with: [dop_common_lib],
)

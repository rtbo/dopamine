
dop_registry_src = files([
    'src/dopamine/registry/v1/package.d',
    'src/dopamine/registry/v1/recipes.d',

    'src/dopamine/registry/app.d',
    'src/dopamine/registry/archive.d',
    'src/dopamine/registry/auth.d',
    'src/dopamine/registry/config.d',
    'src/dopamine/registry/db.d',
    'src/dopamine/registry/storage.d',
    'src/dopamine/registry/utils.d',
])
dop_registry_inc = include_directories('src')

if get_option('alpine')
    dop_registry_link_args = ['-llzma']
else
    dop_registry_link_args = []
endif

dop_registry_versions = ['DopRegistryMain']

if get_option('registry_storage') == 'fs'
    dop_registry_versions += ['DopRegistryFsStorage']
elif get_option('registry_storage') == 'db'
    dop_registry_versions += ['DopRegistryDbStorage']
endif

dop_registry_exe = executable('dop-registry', dop_registry_src,
    install: true,
    include_directories: dop_registry_inc,
    dependencies: [ vibed_http_dep, squiz_dep, cors_dep, jwt_dep, pgd_dep, dop_common_dep ],
    d_module_versions: dop_registry_versions,
    link_args: dop_registry_link_args,
)

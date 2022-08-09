dop_admin_src = files([
    'src/dopamine/admin/app.d',
    'src/dopamine/admin/config.d',
])

dop_admin_inc = include_directories('src')

if get_option('alpine')
    dop_admin_link_args = ['-llzma']
else
    dop_admin_link_args = []
endif

dop_admin_exe = executable('dop-admin', dop_admin_src,
    install: get_option('enable_admin'), # admin is needed by tests, but we only install if explicitely enabled
    include_directories: dop_admin_inc,
    dependencies: [squiz_dep, crypto_dep, pgd_dep, dop_common_dep],
    d_module_versions: ['DopAdminMain'] + dop_registry_storage_versions,
    d_import_dirs: dop_migrations_imp,
    link_args: dop_admin_link_args,
)

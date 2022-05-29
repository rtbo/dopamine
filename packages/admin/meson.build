dop_admin_src = files([
    'src/dopamine/admin/app.d',
    'src/dopamine/admin/config.d',
])

dop_admin_inc = include_directories('src')
dop_admin_imp = include_directories('migrations')

dop_admin_exe = executable('dop-admin', dop_admin_src,
    install: true,
    include_directories: dop_admin_inc,
    dependencies: [squiz_dep, pgd_dep, dop_common_dep],
    d_module_versions: ['DopAdminMain'],
    d_import_dirs: dop_admin_imp,
)

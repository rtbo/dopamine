pgd_src = files([
    'src/pgd/libpq/bindings.d',
    'src/pgd/libpq/defs.d',
    'src/pgd/libpq/package.d',

    'src/pgd/conn.d',
])

pgd_inc = include_directories('src')

pgd_lib = static_library('pgd', pgd_src,
    install: false,
    include_directories: pgd_inc,
)

pgd_dep = declare_dependency(
    link_with: pgd_lib,
    dependencies: libpq_dep,
    include_directories: pgd_inc,
)

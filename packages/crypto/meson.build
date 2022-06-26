crypto_src = files([
    'src/crypto.d'
])

crypto_inc = include_directories('src')

crypto_lib = library('crypto', crypto_src)

crypto_dep = declare_dependency(
    link_with: crypto_lib,
    include_directories: crypto_inc,
)

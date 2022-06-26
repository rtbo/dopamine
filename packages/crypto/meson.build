crypto_src = files([
    'src/crypto.d'
])

crypto_inc = include_directories('src')

crypto_link_args = []

if host_machine.system() == 'windows'
    crypto_link_args += 'bcrypt.lib'
endif

crypto_lib = library('crypto', crypto_src,
    include_directories: crypto_inc,
    link_args: crypto_link_args,
)

crypto_dep = declare_dependency(
    link_with: crypto_lib,
    include_directories: crypto_inc,
    link_args: crypto_link_args,
)

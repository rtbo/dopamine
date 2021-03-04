
project('pkga', ['c'], version:'1.0.0')

pkga_lib = library('pkga', ['pkga.h', 'pkga.c'],
    install: true,
    include_directories: ['.'],
)

pkg = import('pkgconfig')
pkg.generate(name: 'pkga',
              libraries: pkga_lib,
              subdirs: 'pkga',
              version: meson.project_version(),
              description: 'A simple example D library.',
)
install_data('pkga.h', install_dir: 'include/pkga/')

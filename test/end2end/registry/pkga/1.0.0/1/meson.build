
project('pkga', ['c'], version:'1.0.0')

cflags = []
cflags_pkgc = []
if host_machine.system() == 'windows'
    cflags += ['-DIS_DLL', '-DPKGA_LIB']
    cflags_pkgc = ['-DIS_DLL']
endif

pkga_lib = library('pkga', ['pkga.h', 'pkga.c'],
    install: true,
    include_directories: ['.'],
    c_args: cflags,
)

pkg = import('pkgconfig')
pkg.generate(name: 'pkga',
              extra_cflags: cflags_pkgc,
              libraries: pkga_lib,
              subdirs: 'pkga',
              version: meson.project_version(),
              description: 'A simple example C library.',
)
install_data('pkga.h', install_dir: 'include/pkga/')

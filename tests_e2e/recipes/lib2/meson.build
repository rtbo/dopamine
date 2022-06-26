
project('lib2', ['c'], version:'1.0.0')

cflags = []
cflags_lib2 = []
if host_machine.system() == 'windows'
    cflags += ['-DIS_DLL', '-DLIB2_LIB']
    cflags_lib2 = ['-DIS_DLL']
endif

pkga_dep = dependency('pkga')

lib2_lib = library('lib2', ['lib2.h', 'lib2.c'],
    install: true,
    include_directories: ['.'],
    c_args: cflags,
    dependencies: pkga_dep,
)

pkg = import('pkgconfig')
pkg.generate(name: 'lib2',
              libraries: lib2_lib,
              subdirs: 'lib2',
              version: meson.project_version(),
              description: 'A simple example C library.',
)
install_data('lib2.h', install_dir: 'include/lib2/')

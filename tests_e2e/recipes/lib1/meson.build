
project('lib1', ['c'], version:'1.0.0')

cflags = []
cflags_lib1 = []
if host_machine.system() == 'windows'
    cflags += ['-DIS_DLL', '-DLIB1_LIB']
    cflags_lib1 = ['-DIS_DLL']
endif

lib1_lib = library('lib1', ['lib1.h', 'lib1.c'],
    install: true,
    include_directories: ['.'],
    c_args: cflags,
)

pkg = import('pkgconfig')
pkg.generate(name: 'lib1',
              libraries: lib1_lib,
              subdirs: 'lib1',
              version: meson.project_version(),
              description: 'A simple example C library.',
)
install_data('lib1.h', install_dir: 'include/lib1/')

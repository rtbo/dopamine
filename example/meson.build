
project('dopamine_exemple', ['d', 'cpp'])

cpp_lib = static_library('cpp', ['src/c_cpp/source.cpp', 'src/c_cpp/c_source.cpp'],
    install: false,
    include_directories: ['src/c_cpp'],
)

d_lib = static_library('dlib', ['src/d/lib.d'],
    install: false,
    include_directories: ['src/d'],
    link_whole: cpp_lib,
)

d_app = executable('dapp', ['src/d/app.d'],
    install: false,
    include_directories: ['src/d'],
    link_with: d_lib,
)

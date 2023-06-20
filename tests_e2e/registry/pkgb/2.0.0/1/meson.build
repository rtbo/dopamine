
project('pkgb', ['d'], version:'2.0.0')

pkga_dep = dependency('pkga',
    version: '>=2.0.0'
)

pkgb_lib = static_library('pkgb', ['pkgb.d'],
    install: true,
    dependencies: [pkga_dep],
)

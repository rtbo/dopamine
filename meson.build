project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99', 'default_library=static'],
    version: '0.1.0-alpha.1',
)

# check options consistency

if get_option('enable_test')
    if not get_option('enable_client') or not get_option('enable_registry')
        error('both client and registry are needed to enable tests')
    endif
endif

if get_option('enable_client') or get_option('enable_test')
    subdir('3rdparty')
endif

if get_option('enable_client') or get_option('enable_registry') or get_option('enable_admin') or get_option('enable_test')
    squiz_proj = subproject('squiz-box',
        default_options: ['enable_zstd=false'],
    )
    squiz_dep = squiz_proj.get_variable('squiz_dep')
endif

if get_option('enable_client')
    pkgconf_proj = subproject('pkgconf',
        default_options: ['tests=false'],
    )
    pkgconf_lib = pkgconf_proj.get_variable('libpkgconf')
endif

vibed_version = '0.9.6'

if get_option('enable_registry') or get_option('enable_server') or get_option('enable_test')
    vibed_http_dep = dependency('vibe-d:http',
        method: 'dub',
        version: vibed_version,
    )
endif

if get_option('enable_registry') or get_option('enable_admin')
    if host_machine.system() == 'windows'
        src_dir = meson.current_source_dir()
        libpq_file = src_dir / 'windows-x64/lib/libpq.lib'
        libpq_dep = declare_dependency(
            link_args: libpq_file,
        )
    else
        libpq_dep = dependency('libpq',
            version: '>= 14.3',
            method: 'pkg-config',
        )
    endif
endif

vibed_data_dep = dependency('vibe-d:data',
    method: 'dub',
    version: vibed_version,
)

if get_option('enable_test')
    ut_assertions_dep = dependency('unit-threaded:assertions',
        method: 'dub',
        version: '2.0.3',
    )
    stupid_gen_exe = executable('stupid_gen', 'tools/stupid_gen.d',
        d_import_dirs: include_directories('tools'),
    )
endif

if get_option('enable_client') or get_option('enable_test')
    config_gen = executable('config_generator', 'tools/config_generator.d')
endif

subdir('packages')

if get_option('enable_test')
    subdir('tests_e2e')
endif

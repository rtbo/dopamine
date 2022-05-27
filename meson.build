project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99', 'default_library=static'],
    version: '0.1.0-alpha.1',
)

# check options consistency

if get_option('enable_test')
    if not get_option('enable_client') or not get_option('enable_server')
        error('both client and server are needed to enable tests')
    endif
endif

subdir('3rdparty')

squiz_proj = subproject('squiz-box')
squiz_dep = squiz_proj.get_variable('squiz_dep')

vibed_version = '0.9.4'

if get_option('enable_server')
    vibed_http_dep = dependency('vibe-d:http',
        method: 'dub',
        version: vibed_version,
    )
    libpq_dep = dependency('libpq',
        version: '>= 14.3',
        method: 'pkg-config',
    )
endif

if get_option('enable_client')
    vibed_data_dep = dependency('vibe-d:data',
        method: 'dub',
        version: vibed_version,
    )
endif

if get_option('enable_test')
    ut_assertions_dep = dependency('unit-threaded:assertions',
        method: 'dub',
        version: '2.0.3',
    )
endif

discover_unittest = executable('discover_unittest', 'tools/discover_unittest.d')
config_gen = executable('config_generator', 'tools/config_generator.d')

subdir('common')
subdir('lib')

if get_option('enable_client')
    subdir('client')
endif

if get_option('enable_server')

    subdir('server')
endif

if get_option('enable_test')
    subdir('test')
endif

project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

vibed_version = '0.9.4'

vibed_data_dep = dependency('vibe-d:data',
    method: 'dub',
    version: vibed_version,
)
if get_option('enable_server') or get_option('enable_test')
    vibed_http_dep = dependency('vibe-d:http',
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

subdir('lua')
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

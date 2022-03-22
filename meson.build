project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

if not get_option('enable_server') and not get_option('enable_client') and not get_option('enable_test')
    error('At least one of enable_client or enable_server or enable_test options must be active')
endif

vibed_version = '0.9.4'

vibed_data_dep = dependency('vibe-d:data',
    method: 'dub',
    version: vibed_version,
)

if get_option('enable_server') or get_option('enable_test')
    vibed_http_deps = [
        dependency('vibe-d:http',
            method: 'dub',
            version: vibed_version,
        )
    ]
endif

if get_option('enable_test')
    ut_assertions_dep = dependency('unit-threaded:assertions',
        method: 'dub',
        version: '2.0.3',
    )
endif

discover_unittest = executable('discover_unittest', 'tools/discover_unittest.d')

subdir('lua')
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

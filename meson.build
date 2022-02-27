project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

vibed_data_dep = dependency('vibe-d:data',
    method: 'dub',
    version: '0.9.4',
)

vibed_http_dep = dependency('vibe-d:http',
    method: 'dub',
    version: '0.9.4',
)

if host_machine.system() == 'windows'
    vibed_deps += declare_dependency(
        link_args: [
            'user32.lib'
        ],
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

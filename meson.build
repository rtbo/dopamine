project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

if not get_option('enable_server') and not get_option('enable_client') and not get_option('enable_test')
    error('At least one of enable_client or enable_server or enable_test options must be active')
endif

vibed_version = '0.9.4'

# The DUB dependencies should normally be as simple as the following commented definitions.
# But until meson#10045 is merged, we need a really complex dependency scheme that takes into account:
#  - the dependencies of our dependencies
#  - the correct link order

# vibed_data_dep = dependency('vibe-d:data',
#     method: 'dub',
#     version: vibed_version,
# )
# if get_option('enable_server') or get_option('enable_test')
#     vibed_http_dep = dependency('vibe-d:http',
#         method: 'dub',
#         version: vibed_version,
#     )
# endif
# if get_option('enable_test')
#     ut_version = '2.0.3'
#     ut_assertions_deps = dependency('unit-threaded:assertions',
#         method: 'dub',
#         version: ut_version,
#     )
# endif


vibed_data_deps = [
    dependency('vibe-d:data',
        method: 'dub',
        version: vibed_version,
    ),
    dependency('vibe-d:utils',
        method: 'dub',
        version: vibed_version,
    ),
    dependency('stdx-allocator',
        method: 'dub',
        version: '2.77.5',
    ),
]

if get_option('enable_server') or get_option('enable_test')
    vibed_http_deps = [
        dependency('vibe-d:http',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('diet-ng',
            method: 'dub',
            version: '1.8.0',
        ),
        dependency('vibe-d:crypto',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-d:inet',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-d:data',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-d:textfilter',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-d:tls',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-d:stream',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('vibe-core',
            method: 'dub',
            version: '1.22.0',
        ),
        dependency('eventcore',
            method: 'dub',
            version: '0.9.20',
        ),
        dependency('taggedalgebraic',
            method: 'dub',
            version: '0.11.22',
        ),
        dependency('vibe-d:utils',
            method: 'dub',
            version: vibed_version,
        ),
        dependency('stdx-allocator',
            method: 'dub',
            version: '2.77.5',
        ),
    ]
    if host_machine.system() == 'windows'
        vibed_http_deps += declare_dependency(
            link_args: [
                join_paths(meson.source_root(), 'libs/windows-x64/libcrypto.lib'),
                join_paths(meson.source_root(), 'libs/windows-x64/libssl.lib'),
                'user32.lib'
            ],
        )
    else
        vibed_http_deps += declare_dependency(
            link_args: [ '-lssl', '-lcrypto' ],
        )
    endif
endif

if get_option('enable_test')
    ut_version = '2.0.3'
    ut_assertions_deps = [
        dependency('unit-threaded:assertions',
            method: 'dub',
            version: ut_version,
        ),
        dependency('unit-threaded:exception',
            method: 'dub',
            version: ut_version,
        ),
        dependency('unit-threaded:from',
            method: 'dub',
            version: ut_version,
        ),
    ]
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

project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

# vibed_deps = [
#     dependency('stdx-allocator',
#         version: '2.77.5',
#         method: 'dub',
#     ),
#     dependency('eventcore',
#         version: '0.9.20',
#         method: 'dub',
#     ),
#     dependency('vibe-core',
#         version: '1.22.0',
#         method: 'dub',
#     ),
#     dependency('diet-ng',
#         version: '1.8.0',
#         method: 'dub',
#     ),
#     dependency('taggedalgebraic',
#         version: '0.11.22',
#         method: 'dub',
#     ),
#     dependency('vibe-d:utils',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:crypto',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:stream',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:textfilter',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:data',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:tls',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:inet',
#         version: '0.9.4',
#         method: 'dub',
#     ),
#     dependency('vibe-d:http',
#         version: '0.9.4',
#         method: 'dub',
#     ),
# ]
# if host_machine.system() == 'windows'
#     vibed_deps += declare_dependency(
#         link_args: [
#             join_paths(meson.source_root(), 'libs/windows-x64/libcrypto.lib'),
#             join_paths(meson.source_root(), 'libs/windows-x64/libssl.lib'),
#             'user32.lib'
#         ],
#     )
# endif

vibed_deps = [
    dependency('vibe-core',
        version: '1.22.0',
        method: 'dub',
    ),
    dependency('vibe-d:http',
        version: '0.9.4',
        method: 'dub',
    ),
]

discover_unittest = executable('discover_unittest', 'tools/discover_unittest.d')

subdir('lua')
subdir('lib')
subdir('client')
subdir('test')

project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

vibed_deps = [
    dependency('vibe-d:http',
        version: '0.9.4',
        method: 'dub',
    ),
]
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
subdir('client')
subdir('test')

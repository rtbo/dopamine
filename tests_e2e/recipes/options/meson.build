project('options', ['d'],
    version: '1.0.0',
)

if not get_option('enable_lib1') and not get_option('enable_lib2')
    error('at least lib1 or lib2 must be enabled')
endif

if get_option('enable_lib1')
    lib1_lib = static_library('options_lib1', 'thelib1/src/thelib1.d',
        install: true,
    )
endif

if get_option('enable_lib2')
    lib2_lib = static_library('options_lib2', 'thelib2/src/thelib2.d',
        install: true,
    )
endif

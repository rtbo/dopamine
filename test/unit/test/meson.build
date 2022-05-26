
all_mods = custom_target('gen_allmods',
    capture: true,
    output: 'all_mods.d',
    input: dop_ut_src,
    command: [
        discover_unittest, '@INPUT@',
        '--modname', 'test.all_mods',
        '--exclude', 'silly'
    ],
)

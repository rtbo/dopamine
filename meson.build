project('dopamine', ['c', 'd'],
    default_options: ['c_std=c99'],
    version: '0.1.0-alpha.1',
)

dini_dep = dependency('dini',
    version: '~>2.0.0',
    method: 'dub',
)

discover_unittest = executable('discover_unittest', 'tools/discover_unittest.d')

lua_d_versions = ['LUA_53', 'BindBC_Static']

subdir('lua')
subdir('lib')
subdir('client')

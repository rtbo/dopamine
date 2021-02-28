project('dopamine', 'd',
    version: '0.1.0-alpha.1',
)

lua_bindings = get_option('lua_bindings')
lua_version = get_option('lua_version')

lua_d_versions = ['LUA_'+lua_version ]
lua_deps = []

if (lua_bindings == 'static')
    lua_deps += [ dependency('lua' + lua_version) ]
    lua_d_versions += [ 'BindBC_Static' ]
endif

dini_dep = dependency('dini',
    version: '~>2.0.0',
    method: 'dub'
)

discover_unittest = executable('discover_unittest', 'tools/discover_unittest.d')

subdir('lib')
subdir('client')

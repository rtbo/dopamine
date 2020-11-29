project('dopamine', 'd',
    version: '0.1.0',
)

lua_dep = dependency('lua53')

lua_d_versions = ['LUA_53', 'BindBC_Static']
lua_d_dep = [lua_dep] # only needed if static

dini_dep = dependency('dini',
    version: '~>2.0.0',
    method: 'dub'
)

subdir('lua')
subdir('lib')
subdir('client')

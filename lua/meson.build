
dop_lua_src = [
    'src/bindbc/loader/package.d',
    'src/bindbc/loader/sharedlib.d',
    'src/bindbc/loader/system.d',
    'src/bindbc/lua/config.d',
    'src/bindbc/lua/package.d',
    'src/bindbc/lua/v53/binddynamic.d',
    'src/bindbc/lua/v53/bindstatic.d',
    'src/bindbc/lua/v53/package.d',
    'src/bindbc/lua/v53/types.d',
]

dop_lua_inc = include_directories('src')

dop_lua_lib = static_library('dop_lua', dop_lua_src,
    install: false,
    include_directories: dop_lua_inc,
    d_module_versions: ['LUA_53', 'LUA_53_DYNAMIC'],
)

dop_lua_dep = declare_dependency(
    include_directories: dop_lua_inc,
    link_with: dop_lua_lib,
)

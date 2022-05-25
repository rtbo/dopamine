
lua_core_src = [
    'lapi.c',
    'lcode.c',
    'lctype.c',
    'ldebug.c',
    'ldo.c',
    'ldump.c',
    'lfunc.c',
    'lgc.c',
    'llex.c',
	'lmem.c',
    'lobject.c',
    'lopcodes.c',
    'lparser.c',
    'lstate.c',
    'lstring.c',
    'ltable.c',
	'ltm.c',
    'lundump.c',
    'lvm.c',
    'lzio.c',
    'ltests.c',
]


lua_auxlib_src = [
    'lauxlib.c',
]

lua_lib_src = [
    'lbaselib.c',
    'ldblib.c',
    'liolib.c',
    'lmathlib.c',
    'loslib.c',
    'ltablib.c',
    'lstrlib.c',
    'lutf8lib.c',
    'loadlib.c',
    'lcorolib.c',
    'linit.c',
]

lua_c_args = ['-DLUA_COMPAT_5_3']

if host_machine.system() != 'windows'
    lua_c_args += [
        '-DLUA_USE_DLOPEN',
        '-DLUA_USE_POSIX',
    ]
endif

lua_lib = static_library('lua', lua_core_src, lua_auxlib_src, lua_lib_src,
    include_directories: include_directories('.'),
    c_args: lua_c_args,
)

lua_dep = declare_dependency(
    link_with: lua_lib,
)

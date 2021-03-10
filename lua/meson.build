
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

lua_cppargs = []

if host_machine.system() != 'windows'
    lua_cppargs += [
        '-DLUA_USE_DLOPEN',
        '-DLUA_USE_POSIX',
        '-DLUA_COMPAT_5_3',
    ]
endif

lua_lib = static_library('luadop', lua_core_src, lua_auxlib_src, lua_lib_src,
    cpp_args: lua_cppargs,
)


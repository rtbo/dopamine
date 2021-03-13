subdir('src/dopamine')

dop_src = files([
    'src/arsd/terminal.d',

    'src/bindbc/loader/package.d',
    'src/bindbc/loader/sharedlib.d',
    'src/bindbc/loader/system.d',
    'src/bindbc/lua/config.d',
    'src/bindbc/lua/package.d',
    'src/bindbc/lua/v53/binddynamic.d',
    'src/bindbc/lua/v53/bindstatic.d',
    'src/bindbc/lua/v53/package.d',
    'src/bindbc/lua/v53/types.d',

    'src/dopamine/api/defs.d',
    'src/dopamine/api/package.d',
    'src/dopamine/api/transport.d',
    'src/dopamine/lua/lib.d',
    'src/dopamine/lua/package.d',
    'src/dopamine/lua/profile.d',
    'src/dopamine/lua/util.d',
    'src/dopamine/archive.d',
    'src/dopamine/depbuild.d',
    'src/dopamine/depcache.d',
    'src/dopamine/depdag.d',
    'src/dopamine/dependency.d',
    'src/dopamine/deplock.d',
    'src/dopamine/log.d',
    'src/dopamine/login.d',
    'src/dopamine/paths.d',
    'src/dopamine/profile.d',
    'src/dopamine/recipe.d',
    'src/dopamine/semver.d',
    'src/dopamine/state.d',
    'src/dopamine/util.d',
])

dop_inc = include_directories('src')
dop_deps = [ dini_dep, lua_dep ]
dop_imp = include_directories('src/dopamine/lua')

dop_lib = library('dopamine', dop_src,
    install: true,
    include_directories: dop_inc,
    dependencies: dop_deps,
    d_import_dirs: dop_imp,
    d_module_versions: lua_d_versions,
)

dop_dep = declare_dependency(
    include_directories: dop_inc,
    dependencies: dop_deps,
    link_with: [dop_lib],
)

dop_test_src = dop_src + files([
    'test/main.d',
    'test/recipe.d',
    'test/silly.d',
    'test/util.d',
    'test/lua/lib.d',
    'test/lua/ut.d',
])

eh_dep = dependency('exceptionhandling',
    version: '~>1.0.0',
    method: 'dub',
)

# all_mods defined in test
# subdir('test')
# all_mods is hardcoded instead of generating waiting for meson#8435
# dop_test_src += all_mods
dop_test_src += files('test/all_mods.d')

dop_test = executable('doptest', dop_test_src,
    install: false,
    include_directories: [ dop_inc, include_directories('.') ],
    dependencies: dop_deps + [ eh_dep ],
    d_import_dirs: dop_imp,
    d_module_versions: lua_d_versions,
    d_unittest: true,
)

test('dop tests', dop_test,
    args: ['--threads', '1']
)

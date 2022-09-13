local fp = test.path('gen', 'pctest.pc')
local prefix = test.path('gen', 'prefix')
local pc = dop.PkgConfFile:new {
    vars = {
        prefix = prefix,
        includedir = '${prefix}/include',
        libdir = '${prefix}/lib',
    },
    name = 'pc-test',
    version = '1.0.1',
    description = 'A test pkgconfig package',
    cflags = '-I${includedir}',
    libs = '-L${libdir} -lpctest',
}
pc:write(fp)

local expected = string.format(
    [[prefix=%s
includedir=${prefix}/include
libdir=${prefix}/lib

Name: pc-test
Version: 1.0.1
Description: A test pkgconfig package
Cflags: -I${includedir}
Libs: -L${libdir} -lpctest
]],
    prefix
)

local f = assert(io.open(fp, 'r'))
local content = f:read('*a')
f:close()

test.assert_eq(content, expected)

local parsed = dop.PkgConfFile:parse(fp)
test.assert_eq(parsed.vars.prefix, prefix)
test.assert_eq(parsed.vars.includedir, '${prefix}/include')
test.assert_eq(parsed.vars.libdir, '${prefix}/lib')
test.assert_eq(parsed.name, 'pc-test')
test.assert_eq(parsed.version, '1.0.1')
test.assert_eq(parsed.description, 'A test pkgconfig package')
test.assert_eq(table.concat(parsed.cflags, ' '), '-I${includedir}')
test.assert_eq(table.concat(parsed.libs, ' '), '-L${libdir} -lpctest')

test.assert_eq(parsed:expand('${libdir}/libpctest.a'), prefix .. '/lib/libpctest.a')

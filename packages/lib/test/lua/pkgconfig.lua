local fp = test.path('gen', 'pctest.pc')
local prefix = test.path('gen', 'prefix')
local pc = dop.PkgConfig:new({
    prefix = prefix,
    includedir = '${prefix}/include',
    libdir = '${prefix}/lib',
    custom = '${prefix}/custom',
    name = 'pc-test',
    version = '1.0.1',
    description = 'A test pkgconfig package',
    cflags = '-I${includedir}',
    libs = '-L${libdir} -lpctest',
})
pc:write(fp)

local expected = string.format([[prefix=%s
includedir=${prefix}/include
libdir=${prefix}/lib
custom=${prefix}/custom

Name: pc-test
Version: 1.0.1
Description: A test pkgconfig package
Cflags: -I${includedir}
Libs: -L${libdir} -lpctest
]], prefix)

local f = assert(io.open(fp, 'r'))
local content = f:read('*a')
f:close()

test.assert_eq(content, expected)

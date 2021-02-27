local dop = require('dop')

name = 'pkgc'
version = '1.0.0'
description = 'Package C'
langs = {"d"}

dependencies = {
    pkga = '>=1.0'
}

function build(dirs, config, depinfos)
    local profile = config.profile
    local dc = profile.compilers.d.path
    dop.run_cmd{
        'dub', 'build', '--build='..profile.build_type, '--compiler='..dc
    }
end

function pack(dirs, config, dest)
    local install = dop.installer('.', dest)

    install.file('libpkgc.a', 'lib/libpkgc.a');
    install.file('pkgc.d', 'include/d/pkgc-'..version..'/pkgc.d')

    pcdir = dop.path(dest, 'lib', 'pkgconfig')
    libdir = dop.path(dest, 'lib')
    libdir = dop.path(dest, 'include')

    dop.mkdir{
        pcdir, recurse=true
    }
    pc = io.open(dop.path(pcdir, 'pkgc.pc'), 'w')
    pc:write('prefix=', dest, '\n')
    pc:write('libdir=${prefix}/lib\n')
    pc:write('includedir=${prefix}/include\n')
    pc:write('\n')
    pc:write('Name: ', name, '\n')
    pc:write('Description: ', description, '\n')
    pc:write('Version: ', version, '\n')
    pc:write('Libs: -L${libdir} -lpkgc', '\n')
    pc:write('Dflags: -I${includedir}/d/pkgc-'..version, '\n')
    pc:close()
end

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

function pack(dirs, config, depinfos)
    local install = dop.installer('.', dirs.dest)

    install.file('libpkgc.a', 'lib/libpkgc.a');
    install.file('pkgc.d', 'include/d/pkgc-'..version..'/pkgc.d')

    local pcdir = dop.path(dirs.dest, 'lib', 'pkgconfig')
    local libdir = dop.path(dirs.dest, 'lib')
    local libdir = dop.path(dirs.dest, 'include')

    -- pkgapref can very well equal dirs.dest
    local pkgapref = depinfos.pkga.install_dir

    dop.mkdir{
        pcdir, recurse=true
    }
    local pc = io.open(dop.path(pcdir, 'pkgc.pc'), 'w')
    pc:write('prefix=', dirs.dest, '\n')
    pc:write('libdir=${prefix}/lib\n')
    pc:write('includedir=${prefix}/include\n')
    pc:write('pkga_prefix=', pkgapref, '\n')
    pc:write('\n')
    pc:write('Name: ', name, '\n')
    pc:write('Description: ', description, '\n')
    pc:write('Version: ', version, '\n')
    pc:write('Libs: -L${libdir} -lpkgc -L${pkga_prefix} -lpkga', '\n')
    pc:write('Cflags: -I${includedir}/d/pkgc-'..version, '\n')
    pc:close()
end

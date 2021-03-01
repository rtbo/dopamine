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

    local pc = dop.PkgConfig:new {
        prefix = dirs.dest,
        includedir = '${prefix}/include',
        libdir = '${prefix}/lib',
        pkga_prefix = pkgapref,
        name = name,
        version = version,
        description = description,
        libs = '-L${libdir} -lpkgc -L${pkga_prefix} -lpkga',
        cflags = '-I${includedir}/d/pkgc-'..version,
    }
    pc:write(dop.path(pcdir, 'pkgc.pc'))
end

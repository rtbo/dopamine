local dop = require('dop')

name = 'pkgc'
version = '1.0.0'

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
end

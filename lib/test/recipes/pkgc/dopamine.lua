return {
    name = 'pkgc',
    version = '1.0.0',
    description = 'Package C',
    langs = {'d'},

    dependencies = {pkga = '>=1.0'},

    build = function(self, dirs, config, depinfos)
        local profile = config.profile
        local dc = profile.compilers.d.path
        dop.run_cmd {
            'dub',
            'build',
            '--build=' .. profile.build_type,
            '--compiler=' .. dc,
        }
    end,

    package = function(self, dirs, config, depinfos)
        local install = dop.installer('.', dirs.dest)

        install.file(dop.assert(dop.find_libfile('.', 'pkgc', 'static')), 'lib');
        install.file('pkgc.d', 'include/d/pkgc-' .. self.version)

        local pc = dop.PkgConfig:new{
            prefix = dirs.dest,
            includedir = '${prefix}/include',
            libdir = '${prefix}/lib',
            name = self.name,
            version = self.version,
            description = self.description,
            requires = 'pkga',
            libs = '-L${libdir} -lpkgc',
            cflags = '-I${includedir}/d/pkgc-' .. self.version,
        }
        pc:write(dop.path(dirs.dest, 'lib', 'pkgconfig', 'pkgc.pc'))
    end,
}

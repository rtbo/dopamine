return {
    name = 'zlib',
    version = '1.2.11',
    description =
        'A Massively Spiffy Yet Delicately Unobtrusive Compression Library',
    authors = {'Jean-loup Gailly', 'Mark Adler'},
    license = 'MIT',
    copyright = 'Copyright (C) 1995-2017 Jean-loup Gailly and Mark Adler',
    langs = {'c'},

    revision = '1',

    source = function (self)
        local folder = 'zlib-' .. self.version
        local archive = folder .. '.tar.gz'
        local url = 'https://github.com/madler/zlib/archive/refs/tags/v' .. self.version .. '.tar.gz'

        dop.download {url, dest = archive}
        dop.checksum {archive, sha1 = '56559d4c03beaedb0be1c7481d6a371e2458a496'}
        dop.extract_archive {archive, outdir = '.'}

        return folder
    end,

    build = function (self, dirs, config)
        local cmake = dop.CMake:new(config.profile)

        cmake:configure{ src_dir = dirs.src }
        cmake:build()
    end,

    package = function (self, dirs, config)
        dop.install_file(dop.path(dirs.src, 'zlib.h'), 'include/zlib.h')

        local install = dop.installer(dirs.build, '.')
        install.file('zconf.h', 'include')
        install.file('zlib.pc', 'share/pkgconfig')
        if dop.posix then
            install.file('libz.so.'..self.version, 'lib')
            install.file('libz.so.1', 'lib')
            install.file('libz.so', 'lib')
            install.file('libz.a', 'lib')
        elseif dop.windows then
            install.file('zlib1.dll', 'bin')
            install.file('zlibstatic.lib', 'lib')
        end
    end,
}

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

        build_dir = dop.mkdir {"build", recurse = true}

        dop.from_dir(build_dir, function()
            cmake:configure{ src_dir = dirs.src }
            cmake:build()
        end)
    end,
}

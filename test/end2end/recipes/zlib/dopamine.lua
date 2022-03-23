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

        dop.download {'https://zlib.net/' .. archive, dest = archive}
        dop.checksum {archive, sha1 = 'e6d119755acdf9104d7ba236b1242696940ed6dd'}
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

local dop = {}

-- adding dop_native funcs and constants to dop
for k, v in pairs(require('dop_native')) do
    dop[k] = v
end

function dop.assert(pred, msg, level)
    if pred then return pred end
    if not msg then
        msg = 'Error: assertion failed'
    elseif type(msg) == 'number' then
        level = msg - 1
        msg = 'Error: assertion failed'
    else
        level = level and level-1 or -2
    end
    error(msg, level)
end

local function create_class(name)
    local cls = {}
    cls.__index = cls
    dop[name] = cls
    return cls
end

-- perform closure func from the directory dir
-- and return its result(s)
-- will chdir back to previous even if func raise an error
function dop.from_dir(dir, func)
    local cwd = dop.cwd()

    dop.chdir(dir)
    local pres = {pcall(func)}
    dop.chdir(cwd)

    if pres[1] then
        -- shift left and unpack results
        local res = {}
        for i = 2, #pres do
            res[i - 1] = pres[i]
        end
        return table.unpack(res)
    else
        error(pres[2], -2)
    end
end

-- Return an object containing a file function to install files and a dir function to install dirs.
function dop.installer(src_dir, dest_dir)
    local inst = {
        file = function(src, dest, options)
            if not options or not options.rename == true then
                local name = dop.base_name(src)
                dest = dop.path(dest, name)
            end
            dop.install_file(dop.path(src_dir, src), dop.path(dest_dir, dest))
        end,
        dir = function(src, dest)
            dop.install_dir(dop.path(src_dir, src), dop.path(dest_dir, dest))
        end,
    }
    return inst
end


local function find_libfile_posix (dir, name, libtype)
    if not libtype or libtype == 'shared' then
        local p = dop.path(dir, 'lib' .. name .. '.so')
        if dop.is_file(p) then return p end
    elseif not libtype or libtype == 'static' then
        local p = dop.path(dir, 'lib' .. name .. '.a')
        if dop.is_file(p) then return p end
    end
end

local function find_libfile_win (dir, name, libtype)
    if not libtype or libtype == 'shared' then
        local p = dop.path(dir, name .. '.dll')
        if dop.is_file(p) then return p end
    elseif not libtype or libtype == 'static' then
        local p = dop.path(dir, name .. '.lib')
        if dop.is_file(p) then return p end
        p = dop.path(dir, 'lib' .. name .. '.a')
        if dop.is_file(p) then return p end
    end
end

-- Function that find a library file in the specified directory
function dop.find_libfile(dir, name, libtype)
    if dop.posix then
        return find_libfile_posix(dir, name, libtype)
    else
        return find_libfile_win(dir, name, libtype) 
    end
end


local Git = create_class('Git')

-- Return a function that checks if the git repo is clean and return the commit revision
-- Assign this to your package revision if you want to use git as package revision tracker
function Git.revision()
    return function()
        local status = dop.run_cmd({
            'git',
            'status',
            '--porcelain',
            catch_output = true,
        })
        if status ~= '' then
            error('Git repo not clean', 2)
        end
        return dop.trim(dop.run_cmd({
            'git',
            'rev-parse',
            'HEAD',
            catch_output = true,
        }))
    end
end

local CMake = create_class('CMake')

function CMake:new(profile)
    o = {}
    setmetatable(o, self)

    if profile == nil then
        error('profile is mandatory', -2)
    end
    if profile.build_type == nil then
        error('wrong profile parameter', -2)
    end
    o.profile = profile
    o.defs = {['CMAKE_BUILD_TYPE'] = profile.build_type}

    return o
end

function CMake:configure(params)
    if params == nil then
        error('CMake:configure must be passed a parameter table', -2)
    end
    if params.src_dir == nil then
        error('CMake:configure: src_dir is a mandatory parameter', -2)
    end
    if params.install_dir == nil then
        error('CMake:configure: install_dir is a mandatory parameter', -2)
    end
    self.src_dir = params.src_dir
    self.install_dir = params.install_dir

    self.defs['CMAKE_INSTALL_PREFIX'] = self.install_dir

    if params.defs then
        for k, v in pairs(params.defs) do
            self.defs[k] = v
        end
    end

    local gen = params.gen or 'Ninja'

    local cmd = {'cmake', '-G', gen}

    for k, v in pairs(self.defs) do
        if type(v) == 'boolean' then
            if v then
                v = 'ON'
            else
                v = 'OFF'
            end
        elseif type(v) == 'number' then
            v = tostring(v)
        end
        table.insert(cmd, '-D' .. k .. '=' .. v)
    end

    table.insert(cmd, self.src_dir)

    cmd['env'] = dop.profile_environment(self.profile)

    dop.run_cmd(cmd)
end

function CMake:build()
    cmd = {'cmake', '--build', '.'}
    dop.run_cmd(cmd)
end

function CMake:install()
    cmd = {'cmake', '--build', '.', '--target', 'install'}
    dop.run_cmd(cmd)
end

local Meson = create_class('Meson')

function Meson:new(profile)
    o = {}
    setmetatable(o, self)

    o.profile = assert(profile, 'profile parameter is mandatory')
    o.options = {}
    o.defs = {}

    if profile then
        o.options['--buildtype'] = profile.build_type
    end

    return o
end

local function is_system_wide(prefix)
    return prefix:sub(1, 4) == '/usr' or prefix == '/'
end

function Meson:setup(params)
    assert(params, 'Meson:setup must be passed a parameter table')
    self.build_dir = assert(params.build_dir,
                            'build_dir is a mandatory parameter')
    self.install_dir = assert(params.install_dir,
                              'install_dir is a mandatory parameter')

    self.options['--prefix'] = params.install_dir

    -- on Debian/Ubuntu, meson adds a multi-arch path suffix to the libdir
    -- e.g. [prefix]/lib/x86_64-linux-gnu
    -- we don't want this with dopamine if we are not installing
    -- to system wide location. see meson #5925
    if dop.os == 'Linux' and not is_system_wide(params.install_dir) then
        self.options['--libdir'] = dop.path(params.install_dir, 'lib')
    end

    if params.options then
        for k, v in pairs(params.options) do
            self.options[k] = v
        end
    end
    if params.defs then
        for k, v in pairs(params.defs) do
            self.defs[k] = v
        end
    end

    local cmd = {'meson', 'setup', self.build_dir}

    for k, v in pairs(self.options) do
        table.insert(cmd, k .. '=' .. v)
    end
    for k, v in pairs(self.defs) do
        table.insert(cmd, '-D' .. k .. '=' .. v)
    end

    cmd['env'] = dop.profile_environment(self.profile)

    dop.run_cmd(cmd)
end

function Meson:compile()
    dop.run_cmd({'meson', 'compile'})
end

function Meson:install()
    dop.run_cmd({'meson', 'install'})
end

local PkgConfig = create_class('PkgConfig')

function PkgConfig:new(options)
    setmetatable(options, self)

    if options.prefix == nil then
        error('PkgConfig needs a prefix', -2)
    end
    if options.name == nil then
        error('PkgConfig needs a name', -2)
    end
    if options.version == nil then
        error('PkgConfig needs a version', -2)
    end
    if options.libs == nil or options.cflags == nil then
        -- TODO warn
    end

    return options
end

function PkgConfig:write(filename)
    dop.mkdir {dop.dir_name(filename), recurse = true}

    local pc = io.open(filename, 'w')

    -- everything not standard is a custom key variable
    local stdfields = {
        prefix = 1,
        exec_prefix = 1,
        includedir = 1,
        libdir = 1,
        name = 1,
        version = 1,
        description = 1,
        url = 1,
        requires = 1,
        ['requires.private'] = 1,
        conflicts = 1,
        cflags = 1,
        libs = 1,
        ['libs.private'] = 1,
    }

    function write_field(field, sep)
        local v = self[field]
        if v ~= nil then
            sep = sep or ': '
            if sep == ': ' then
                field = field:gsub('^%l', string.upper)
            end
            pc:write(field, sep, v, '\n')
        end
    end

    write_field('prefix', '=')
    write_field('exec_prefix', '=')
    write_field('includedir', '=')
    write_field('libdir', '=')

    -- writing custom fields as variable declaration
    for k, v in pairs(self) do
        if stdfields[k] == nil then
            write_field(k, '=')
        end
    end

    pc:write('\n')

    write_field('name')
    write_field('version')
    write_field('description')
    if self[url] ~= nil then
        pc:write('URL: ', self[url], '\n')
    end
    write_field('requires')
    write_field('requires.private')
    write_field('conflicts')
    write_field('cflags')
    write_field('libs')
    write_field('libs.private')

    pc:close()
end

return dop

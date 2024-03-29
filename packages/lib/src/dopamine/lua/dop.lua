local dop = {}
local dop_native = require('dop_native')

-- adding dop_native funcs and constants to dop
for k, v in pairs(dop_native) do
    if k:find('priv_', 1, true) ~= 1 then
        dop[k] = v
    end
end

local function create_class(name)
    local cls = {}
    cls.__index = cls
    dop[name] = cls
    return cls
end

function dop.starts_with(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function dop.ends_with(str, suffix)
    return suffix == '' or str:sub(-#suffix) == suffix
end

function dop.assert(pred, msg, level)
    if pred then
        return pred
    end
    if not msg then
        msg = 'Error: assertion failed'
    elseif type(msg) == 'number' then
        level = msg - 1
        msg = 'Error: assertion failed'
    else
        level = level and level - 1 or -2
    end
    error(msg, level)
end

function dop.git_ls_files(opts)
    return function()
        local cmd = {
            'git',
            'ls-files',
        }
        if opts and opts.submodules then
            table.insert(cmd, '--recurse-submodules')
        end
        cmd.catch_output = true
        if opts and opts.workdir then
            cmd.workdir = opts.workdir
        end
        local cmd_out = dop.run_cmd(cmd)
        local files = {}
        for l in cmd_out:gmatch('[^\r\n]+') do
            table.insert(files, l)
        end
        return files
    end
end

-- perform closure func from the directory dir
-- and return its result(s)
-- will chdir back to previous even if func raise an error
function dop.from_dir(dir, func)
    local cwd = dop.cwd()

    dop.chdir(dir)
    local pres = { pcall(func) }
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

function dop.to_string(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dop.to_string(v) .. ',\n'
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function find_libfile_posix(dir, name, libtype)
    if not libtype or libtype == 'shared' then
        local p = dop.path(dir, 'lib' .. name .. '.so')
        if dop.is_file(p) then
            return p
        end
    end
    if not libtype or libtype == 'static' then
        local p = dop.path(dir, 'lib' .. name .. '.a')
        if dop.is_file(p) then
            return p
        end
    end
end

local function find_libfile_win(dir, name, libtype)
    if not libtype or libtype == 'shared' then
        local p = dop.path(dir, name .. '.dll')
        if dop.is_file(p) then
            return p
        end
    end
    if not libtype or libtype == 'static' then
        local p = dop.path(dir, name .. '.lib')
        if dop.is_file(p) then
            return p
        end
        p = dop.path(dir, 'lib' .. name .. '.a')
        if dop.is_file(p) then
            return p
        end
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

local PkgConfFile = create_class('PkgConfFile')

local pc_str_fields = {
    'name',
    'version',
    'description',
    'url',
    'license',
    'maintainer',
    'copyright',
}

local pc_lst_fields = {
    'cflags',
    'cflags.private',
    'libs',
    'libs.private',
    'requires',
    'requires.private',
    'provides',
    'conflicts',
}

local pc_argv_fields = {
    'cflags',
    'cflags.private',
    'libs',
    'libs.private',
}

function PkgConfFile:parse(path)
    local parsed = dop_native.priv_pkgconf_read_file(path)
    setmetatable(parsed, self)
    setmetatable(parsed.vars, vars_mt)
    return parsed
end

function PkgConfFile:new(options)
    options.vars = options.vars or {}

    setmetatable(options, self)
    setmetatable(options.vars, vars_mt)

    if options.name == nil then
        error('Name field is required by PkgConfig', -2)
    end
    if options.version == nil then
        error('Version field is required by PkgConfig', -2)
    end
    if options.description == nil then
        error('Description field is required by PkgConfig', -2)
    end

    if options.vars.prefix == nil then
        io.stderr:write('Warning: PkgConfFile without prefix variable')
    end

    for k, o in pairs(options) do
        if k == 'vars' then
            goto continue
        end
        for _, s in ipairs(pc_str_fields) do
            if k == s then
                goto continue
            end
        end
        for _, s in ipairs(pc_lst_fields) do
            if k == s then
                goto continue
            end
        end
        error('Unknown pkg-config field: ' .. k, -2)
        ::continue::
        for _, s in ipairs(pc_argv_fields) do
            if k == s and type(o) == 'string' then
                options[k] = dop_native.priv_pkgconf_argv_split(o)
            end
        end
    end

    return options
end

function PkgConfFile:expand(value)
    while 1 do
        local num
        value, num = value:gsub('%${(%w+)}', self.vars)
        if num == 0 then
            return value
        end
    end
end

local function translate_msvc_libs(pc, field)
    local libflags = pc[field]
    local msvc = {}
    local libpaths = {}
    local libs = {}
    for _, flag in ipairs(libflags) do
        local libpath = flag:match('-L(.+)')
        if libpath then
            table.insert(libpaths, libpath)
            goto continue
        end
        local lib = flag:match('-l(.+)')
        if lib then
            table.insert(libs, lib)
            goto continue
        end
        table.insert(msvc, flag)
        ::continue::
    end
    for _, lib in ipairs(libs) do
        local flag = nil
        local elib = pc:expand(lib)

        if dop.is_file(lib) then
            flag = elib
        else
            for _, libpath in ipairs(libpaths) do
                local elibpath = pc:expand(libpath)
                local path = find_libfile_win(elibpath, elib)
                if path then
                    flag = libpath .. '/' .. dop.base_name(path)
                    break
                end
            end
        end
        table.insert(msvc, flag or lib .. '.lib')
    end
    return msvc
end

function PkgConfFile:translate_msvc()
    if self.libs then
        self.libs = translate_msvc_libs(self, 'libs')
    end
    if self['libs.private'] then
        self['libs.private'] = translate_msvc_libs(self, 'libs.private')
    end
end

-- function that compute variable order such as each can be evaluated without look-ahead
-- once written in a file.
-- not strictly necessary, but consistent order is better than random hash-key order
local function var_order(vars, var)
    local val = vars[var]
    local pat = '%${(%w+)}'
    local m = string.match(val, pat)
    if not m then
        return 0
    else
        return 1 + var_order(vars, m)
    end
end

function PkgConfFile:write(filename)
    dop.mkdir { dop.dir_name(filename), recurse = true }
    local pc = io.open(filename, 'w')

    local vars = {}
    for k, v in pairs(self.vars) do
        table.insert(
            vars,
            { name = k, value = v, order = var_order(self.vars, k) }
        )
    end
    table.sort(vars, function(a, b)
        if a.order == b.order then
            return a.name < b.name
        end
        return a.order < b.order
    end)

    for _, var in ipairs(vars) do
        pc:write(var.name, '=', var.value, '\n')
    end

    pc:write('\n')

    for _, f in ipairs(pc_str_fields) do
        local v = self[f]
        if v then
            local fu = f:gsub('^%l', string.upper)
            pc:write(fu, ': ', v, '\n')
        end
    end
    for _, f in ipairs(pc_lst_fields) do
        local v = self[f]
        if v then
            local fu = f:gsub('^%l', string.upper)
            if type(v) == 'table' then
                pc:write(fu, ': ', table.concat(v, ' '), '\n')
            else
                pc:write(fu, ': ', v, '\n')
            end
        end
    end
    pc:close()
end

function dop.pkg_config_path(dep_infos)
    if not dep_infos then
        return ''
    end
    local path = {}
    for k, v in pairs(dep_infos.dop) do
        if v.install_dir then
            table.insert(path, dop.path(v.install_dir, 'lib', 'pkgconfig'))
        end
    end
    for k, v in pairs(dep_infos.dub) do
        if v.install_dir then
            table.insert(path, dop.path(v.install_dir, 'lib', 'pkgconfig'))
        end
    end
    return table.concat(path, dop.path_sep)
end

local function translate_pkgconf_msvc(path)
    local pc = PkgConfFile:parse(path)
    if pc.libs then
        pc.libs = translate_msvc_libs(pc, 'libs')
    end
    if pc['libs.private'] then
        pc['libs.private'] = translate_msvc_libs(pc, 'libs.private')
    end
    pc:write(path)
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
    o.defs = { ['CMAKE_BUILD_TYPE'] = profile.build_type }

    return o
end

function CMake:configure(params)
    if params == nil then
        error('CMake:configure must be passed a parameter table', -2)
    end
    if params.src_dir == nil then
        error('CMake:configure: src_dir is a mandatory parameter', -2)
    end
    self.src_dir = params.src_dir

    if params.install_dir then
        self.install_dir = params.install_dir
        self.defs['CMAKE_INSTALL_PREFIX'] = self.install_dir
    end

    if params.defs then
        for k, v in pairs(params.defs) do
            self.defs[k] = v
        end
    end

    local gen = params.gen or 'Ninja'

    local cmd = { 'cmake', '-G', gen }

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
    cmd = { 'cmake', '--build', '.' }
    dop.run_cmd(cmd)
end

function CMake:install()
    cmd = { 'cmake', '--build', '.', '--target', 'install' }
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

function Meson:setup(params, env)
    assert(params, 'Meson:setup must be passed a parameter table')

    self.build_dir =
        assert(params.build_dir, 'build_dir is a mandatory parameter')
    self.src_dir = assert(params.src_dir, 'src_dir is a mandatory parameter')

    if params.install_dir then
        self.install_dir = params.install_dir
        self.options['--prefix'] = params.install_dir

        -- on Debian/Ubuntu, meson adds a multi-arch path suffix to the libdir
        -- e.g. [prefix]/lib/x86_64-linux-gnu
        -- we don't want this with dopamine if we are not installing
        -- to system wide location. see meson #5925
        if dop.os == 'Linux' and not is_system_wide(params.install_dir) then
            self.options['--libdir'] = dop.path(params.install_dir, 'lib')
        end
    end

    if params.pkg_config_path then
        self.options['--pkg-config-path'] = params.pkg_config_path
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

    local cmd = { 'meson', 'setup' }
    for k, v in pairs(self.options) do
        table.insert(cmd, k .. '=' .. tostring(v))
    end
    for k, v in pairs(self.defs) do
        table.insert(cmd, '-D' .. k .. '=' .. tostring(v))
    end

    table.insert(cmd, self.build_dir)
    table.insert(cmd, self.src_dir)

    local cmd_env = dop.profile_environment(self.profile)
    if env then
        for k, v in pairs(env) do
            cmd_env[k] = v
        end
    end

    cmd.env = cmd_env
    self.env = cmd_env

    dop.run_cmd(cmd)
end

function Meson:compile()
    dop.run_cmd {
        'meson',
        'compile',
        env = self.env,
    }
end

function Meson:install()
    dop.run_cmd {
        'meson',
        'install',
        env = self.env,
    }
    -- adapting pkg-config file for MSVC and D
    if not dop.windows or not self.install_dir or not self.profile.tools.dc then
        return
    end
    local pkgc_dir = dop.path(self.install_dir, 'lib', 'pkgconfig')
    if not dop.is_dir(pkgc_dir) then
        return
    end
    for f in dop.dir_entries(pkgc_dir) do
        if f.is_file and dop.ends_with(f.name, '.pc') then
            translate_pkgconf_msvc(f.path)
        end
    end
end

return dop

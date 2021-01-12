local dop = {}

-- adding dop_native funcs and constants to dop
for k, v in pairs(require('dop_native')) do
    dop[k] = v
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
        for i=2,#pres do
            res[i-1] = pres[i]
        end
        return table.unpack(res)
    else
        error(pres[2])
    end
end

-- get hash of last git commit
function dop.git_last_commit()
    return dop.run_cmd({'git', 'rev-parse', 'HEAD', catch_output = true})
end

CMake = {}
CMake.__index = CMake
dop.CMake = CMake

function CMake:new(profile)
    o = {}
    setmetatable(o, self)

    o.profile = assert(profile, 'profile is mandatory')
    o.defs = {
        ['CMAKE_BUILD_TYPE'] = profile.build_type
    }

    return o
end

function CMake:configure(params)

    assert(params, 'CMake:configure must be passed a parameter table')
    self.src_dir = assert(params.src_dir, 'src_dir is a mandatory parameter')
    self.install_dir = assert(params.install_dir,
                              'install_dir is a mandatory parameter')
    local cwd = dop.cwd()
    self.build_dir = params.build_dir or cwd

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

    cmd['workdir'] = self.build_dir
    cmd['env'] = dop.profile_environment(self.profile)

    dop.run_cmd(cmd)
end

function CMake:build()
    cmd = {'cmake', '--build', self.build_dir}
    dop.run_cmd(cmd)
end

function CMake:install()
    cmd = {'cmake', '--build', self.build_dir, '--target', 'install'}
    dop.run_cmd(cmd)
end

Meson = {}
Meson.__index = Meson
dop.Meson = Meson

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

function Meson:setup(params)
    assert(params, 'Meson:setup must be passed a parameter table')
    self.build_dir = assert(params.build_dir,
                            'build_dir is a mandatory parameter')
    self.install_dir = assert(params.install_dir,
                              'install_dir is a mandatory parameter')
    local cwd = dop.cwd()
    self.src_dir = params.src_dir or cwd

    self.options['--prefix'] = params.install_dir

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

    cmd['workdir'] = self.src_dir
    cmd['env'] = dop.profile_environment(self.profile)

    dop.run_cmd(cmd)
end

function Meson:compile()
    dop.run_cmd({'meson', 'compile', workdir = self.build_dir})
end

function Meson:install()
    dop.run_cmd({'meson', 'install', workdir = self.build_dir})
end

return dop

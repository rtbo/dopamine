local dop = {}

function dop.Git(params)
    assert(type(params['url']) == 'string', '"url" must specified to Git')
    assert(type(params['revId']) == 'string', '"revId" must specified to Git')
    params.type = 'source'
    params.method = 'git'
    return params
end

function dop.Archive(params)
    assert(type(params['url']) == 'string', '"url" must specified to Archive')
    if (type(params['md5']) ~= 'string' and type(params['sha1']) ~= 'string' and
        type(params['sha256']) ~= 'string') then
        error(
            'Archive must specify one of "md5", "sha1" or "sha256" checksum')
    end
    params.type = 'source'
    params.method = 'archive'
    return params
end

function dop.CMake(params)
    params.type = 'build'
    params.method = 'cmake'
    return params
end

function dop.Meson(params)
    params.type = 'build'
    params.method = 'meson'
    return params
end

return dop

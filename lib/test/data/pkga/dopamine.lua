local dop = require('dop')

name = 'pkga'
version = '1.0.0'

function source()
    return "."
end

function build(params)
    local meson = dop.Meson:new(params.profile)
    meson:setup(params)
    meson:compile()
    meson:install()
end

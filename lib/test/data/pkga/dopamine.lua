local dop = require('dop')

name = 'pkga'
version = '1.0.0'

function build(params)
    local meson = dop.Meson:new(params.profile)
    print(params.build_dir)
    print(params.src_dir)
    print(dop.cwd())
    meson:setup(params)
    meson:compile()
    meson:install()
end

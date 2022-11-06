name = 'warning'
version = '1.0.0'
description = 'a test library'
upstream_url = 'https://github.com/rtbo/dopamine'
license = 'MIT'
tools = { 'cc' }

warn('A warning from recipe')

function build() end

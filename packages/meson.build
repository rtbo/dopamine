
subdir('common')
subdir('jwt')

if get_option('enable_client') or get_option('enable_test')
    subdir('dub')
    subdir('lib')
    subdir('client')
endif

if get_option('enable_admin') or get_option('enable_test') or get_option('enable_server')
    subdir('pgd')
endif

if get_option('enable_admin') or get_option('enable_test')
    subdir('crypto')
    subdir('admin')
endif

if get_option('enable_server')
    subdir('cors')
    subdir('server')
endif

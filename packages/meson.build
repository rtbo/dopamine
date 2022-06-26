
subdir('common')

if get_option('enable_client')
    subdir('lib')
    subdir('client')
endif

if get_option('enable_server')
    subdir('cors')
    subdir('crypto')
    subdir('jwt')
    subdir('pgd')
    subdir('admin')
    subdir('server')
endif

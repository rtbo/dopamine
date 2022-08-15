
if get_option('registry_storage') == 'fs'
    dop_registry_storage_versions = ['DopRegistryFsStorage']
elif get_option('registry_storage') == 'db'
    dop_registry_storage_versions = ['DopRegistryDbStorage']
endif

if get_option('registry_serves_frontend')
    dop_registry_serves_frontend_versions = ['DopRegistryServesFrontend']
else
    dop_registry_serves_frontend_versions = []
endif

if get_option('enable_client') or get_option('enable_admin') or get_option('enable_test') or get_option('enable_registry')
    subdir('common')
    subdir('jwt')
endif

if get_option('enable_client') or get_option('enable_test')
    subdir('dub')
    subdir('lib')
    subdir('client')
endif

if get_option('enable_admin') or get_option('enable_test') or get_option('enable_registry')
    subdir('pgd')
endif

if get_option('enable_admin') or get_option('enable_test')
    dop_migrations_imp = include_directories('registry/migrations')
    subdir('crypto')
    subdir('admin')
endif

if get_option('enable_registry')
    subdir('cors')
    subdir('registry')
endif

if not get_option('registry_serves_frontend') and get_option('enable_frontend_server')
    subdir('frontend_server')
endif

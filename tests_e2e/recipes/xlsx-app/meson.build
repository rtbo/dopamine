project('xlsx-app', ['d'], version: '1.0.0')

xlsxreader_dep = dependency('xlsxreader', method: 'pkg-config')

app = executable('app', 'app.d',
    dependencies: [xlsxreader_dep]
)

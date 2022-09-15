local dir = test.path("lua")
local files = {}

for e in dop.dir_entries(dir) do
    table.insert(files, e)
end

table.sort(files, function (a, b) return a.name < b.name end)

test.assert_eq(files[1].name, 'dir_entries.lua')
test.assert_eq(files[2].name, 'dir_name.lua')
test.assert_eq(files[3].name, 'lib.d')
test.assert_eq(files[4].name, 'pkgconfig.lua')
test.assert_eq(files[5].name, 'ut.d')

test.assert_eq(files[1].path, dop.path(dir, 'dir_entries.lua'))
test.assert_eq(files[2].path, dop.path(dir, 'dir_name.lua'))
test.assert_eq(files[3].path, dop.path(dir, 'lib.d'))
test.assert_eq(files[4].path, dop.path(dir, 'pkgconfig.lua'))
test.assert_eq(files[5].path, dop.path(dir, 'ut.d'))

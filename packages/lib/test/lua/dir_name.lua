test.assert_eq(
    dop.dir_name('relative/dir/file'),
    dop.dir_name('relative/dir/file', 1),
    'relative/dir'
)
test.assert_eq(dop.dir_name('relative/dir/dir/'), 'relative/dir')
test.assert_eq(dop.dir_name('relative/dir/file', 2), 'relative')
test.assert_eq(dop.dir_name('.'), '..')
test.assert_eq(dop.dir_name(''), '..')
test.assert_eq(dop.dir_name('.', 2), dop.path('..', '..')) -- account for different separators
test.assert_eq(dop.dir_name('relative/dir', 2), '.')
test.assert_eq(dop.dir_name('relative/dir', 3), '..')
test.assert_eq(dop.dir_name('relative/dir', 4), dop.path('..', '..'))

if dop.posix then
    test.assert_eq(dop.dir_name('/abs/dir/file', 2), '/abs')
    test.assert_eq(dop.dir_name('/abs/dir/file', 3), '/')
    test.assert_eq(dop.dir_name('/abs/'), '/')
else
    test.assert_eq(dop.dir_name([[C:\dir\file]]), [[C:\dir]])
    test.assert_eq(dop.dir_name([[C:\dir\file]], 2), [[C:\]])
end

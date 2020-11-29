
local dop = require("dop");

name = "example"
description = "Dopamine package example"
version = "0.1.0"
license = "MIT"
authors = { "Rémi Thebault" } -- could be a single string
copyright = "Copyright (C) 2020 Rémi Thebault"
langs = { "d", "c++" }

-- If you package sources that you don't own, you
-- want this to true. This will cause dop to download
-- The sources when a build is necessary.
-- if not specified false is assumed
out_of_tree = false

source = dop.Git {
    url = "https://github.com/rtbo/dopamine",
    revId = "main",
    -- to use a version tag:
    -- revId = "v" .. version,
    subdir = "example",
}

build = dop.Meson {}

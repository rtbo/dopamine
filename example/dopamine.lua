local dop = require("dop");

name = "example"
description = "Dopamine package example"
version = "0.1.0"
license = "MIT"
authors = {"Rémi Thebault"} -- could be a single string
packager = authors[0]
copyright = "Copyright (C) 2020 Rémi Thebault"
langs = {"d", "c++"}

-- how to get access to this package (a folder with this file)
repo = dop.Git {
    url = "https://github.com/rtbo/dopamine",
    revId = "main",
    -- to use a version tag:
    -- revId = "v" .. version,
    subdir = "example"
}

-- how to get access to the package source code
-- it may be different than repo e.g. if you
-- package source code that you don't own.
source = repo

build = dop.Meson {}

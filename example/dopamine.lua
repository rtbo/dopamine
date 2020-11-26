
local dop = require("dop");

name = "example"
description = "Dopamine package example"
version = "0.1.0"
license = "MIT"
copyright = "Copyright (C) 2020 Rémi Thebault"
langs = { "d", "cpp" }

source = dop.Git {
    url = "https://github.com/rtbo/dopamine",
    revId = "main",
    subdir = "example",
}

build = dop.Meson {}

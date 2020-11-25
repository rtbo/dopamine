
name = "example"
description = "Dopamine package example"
version = "0.1.0"
license = "MIT"
copyright = "Copyright (C) 2020 Rémi Thebault"

source = Git {
    url = "https://github.com/rtbo/dopamine",
    revId = "master",
    subdir = "example",
}

build = Meson {}

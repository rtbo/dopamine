// dfmt off
//          Copyright Michael D. Parker 2018.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module bindbc.lua.config;

enum LuaSupport {
    noLibrary,
    badLibrary,
    lua51 = 51,
    lua52 = 52,
    lua53 = 53,
}

version(LUA_51) {
    enum luaSupport = LuaSupport.lua51;
}
version(LUA_52) {
    enum luaSupport = LuaSupport.lua52;
}
version(LUA_53) {
    enum luaSupport = LuaSupport.lua53;
}

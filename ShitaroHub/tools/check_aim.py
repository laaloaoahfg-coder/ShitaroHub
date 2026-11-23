#!/usr/bin/env python3
"""Syntax-check the Lua sources and run the mocked aim regression suite.

Requires CPython 3.9+ and a system Lua 5.4 shared library (or --lua-library).
No Roblox, executor, network, pip dependencies or target game is used.
"""
import argparse
import ctypes as C
import ctypes.util
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lua-library')
    args = parser.parse_args()
    name = args.lua_library or ctypes.util.find_library('lua-5.4') or ctypes.util.find_library('lua5.4')
    if not name:
        parser.error('Lua 5.4 shared library not found; provide --lua-library PATH')
    lua = C.CDLL(name)
    lua.luaL_newstate.argtypes = []; lua.luaL_newstate.restype = C.c_void_p
    lua.luaL_openlibs.argtypes = [C.c_void_p]
    lua.luaL_loadbufferx.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_char_p, C.c_char_p]
    lua.luaL_loadbufferx.restype = C.c_int
    lua.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ssize_t, C.c_void_p]
    lua.lua_pcallk.restype = C.c_int
    lua.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.POINTER(C.c_size_t)]
    lua.lua_tolstring.restype = C.c_char_p
    lua.lua_settop.argtypes = [C.c_void_p, C.c_int]
    lua.lua_close.argtypes = [C.c_void_p]
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    state = lua.luaL_newstate()
    if not state:
        raise SystemExit('Could not allocate Lua state')
    lua.luaL_openlibs(state)

    def check(status, where):
        if status:
            message = lua.lua_tolstring(state, -1, None)
            raise RuntimeError(where + ': ' + (message.decode('utf-8', 'replace') if message else 'unknown Lua error'))

    try:
        paths = sorted(root.rglob('*.lua'))
        for path in paths:
            data = path.read_bytes()
            check(lua.luaL_loadbufferx(state, data, len(data), str(path.relative_to(root)).encode(), b't'), 'Syntax')
            lua.lua_settop(state, 0)
        print(f'PASS: syntax parsed for {len(paths)} Lua files (Lua 5.4, not Luau compiler)', flush=True)
        for name in ('aim_regression.lua', 'esp_player_regression.lua', 'esp_draw_player_regression.lua', 'block_strike_diagnostic_test.lua', 'checkers_research_test.lua', 'checkers_engine_test.lua', 'checkers_controller_test.lua', 'checkers_module_test.lua', 'checkers_captured_replay_test.lua', 'checkers_american_replay_test.lua', 'checkers_log_test.lua', 'checkers_input_test.lua'):
            path = root / 'tests' / name
            data = path.read_bytes()
            chunk_name = ('@tests/' + name).encode()
            check(lua.luaL_loadbufferx(state, data, len(data), chunk_name, b't'), 'Test load: ' + name)
            check(lua.lua_pcallk(state, 0, 0, 0, 0, None), 'Regression suite: ' + name)
    finally:
        lua.lua_close(state)


if __name__ == '__main__':
    main()

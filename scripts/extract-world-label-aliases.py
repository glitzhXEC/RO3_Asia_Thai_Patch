"""Read localization tables in an isolated Lua state; never attach to the game."""
import ctypes as c
import argparse
import hashlib
import json
import os
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--game-root', type=Path, default=repo.parent)
parser.add_argument('--find', help='Inspect matching original labels without changing the export')
parser.add_argument('--item-names', action='store_true', help='Export original item names for stall translation')
parser.add_argument('--skill-names', action='store_true', help='Export skill and auto-battle names')
options = parser.parse_args()
if options.item_names and options.skill_names:
    parser.error('Choose one export at a time')
root = options.game_root.resolve()
plugins = root / 'Client/ro3_Data/Plugins/x86_64'
cookie = os.add_dll_directory(str(plugins))
lua = c.WinDLL(str(plugins / 'xlua.dll'))
L = c.c_void_p
for name, result, args in (
    ('luaL_newstate', L, []), ('luaL_openlibs', None, [L]), ('lua_close', None, [L]),
    ('luaL_loadbufferx', c.c_int, [L, c.c_char_p, c.c_size_t, c.c_char_p, c.c_char_p]),
    ('lua_pcall', c.c_int, [L, c.c_int, c.c_int, c.c_int]),
    ('lua_gettop', c.c_int, [L]), ('lua_settop', None, [L, c.c_int]),
    ('lua_getglobal', c.c_int, [L, c.c_char_p]), ('lua_getfield', c.c_int, [L, c.c_int, c.c_char_p]),
    ('lua_pushnil', None, [L]), ('lua_next', c.c_int, [L, c.c_int]),
    ('lua_type', c.c_int, [L, c.c_int]), ('lua_tointegerx', c.c_longlong, [L, c.c_int, c.c_void_p]),
    ('lua_tolstring', c.c_void_p, [L, c.c_int, c.POINTER(c.c_size_t)]),
):
    function = getattr(lua, name)
    function.restype, function.argtypes = result, args


def string(state, index):
    size = c.c_size_t()
    pointer = lua.lua_tolstring(state, index, c.byref(size))
    return c.string_at(pointer, size.value).decode('utf-8') if pointer else None


def checked(state, status):
    if status:
        raise RuntimeError(string(state, -1))


tables = {}
hashes = {}
for locale in ('en', 'zh_CN', 'zh_TW'):
    state = lua.luaL_newstate()
    try:
        lua.luaL_openlibs(state)
        path = root / ('Client/ro3_Data/StreamingAssets/Recovery/LuaPayload/Localization_' + locale + '.lua.bytes')
        payload = path.read_bytes()
        hashes[locale] = hashlib.sha256(payload).hexdigest()
        checked(state, lua.luaL_loadbufferx(state, payload, len(payload), b'@offline-world-names', b'b'))
        checked(state, lua.lua_pcall(state, 0, 1, 0))
        if lua.lua_type(state, -1) != 5:
            lua.lua_getglobal(state, b'LanguageKV')
        table = lua.lua_gettop(state)
        lua.lua_getfield(state, table, b'm_kValues')
        if lua.lua_type(state, -1) == 5:
            table = lua.lua_gettop(state)
        else:
            lua.lua_settop(state, -2)
        rows = {}
        if lua.lua_type(state, table) != 5:
            raise RuntimeError('Localization table was not returned or exported')
        lua.lua_pushnil(state)
        while lua.lua_next(state, table):
            key = str(lua.lua_tointegerx(state, -2, None)) if lua.lua_type(state, -2) == 3 else string(state, -2)
            if lua.lua_type(state, -1) == 4:
                rows[key] = string(state, -1)
            elif lua.lua_type(state, -1) == 5:
                nested = lua.lua_gettop(state)
                lua.lua_getfield(state, nested, b'_kDes')
                if lua.lua_type(state, -1) == 4:
                    rows[key] = string(state, -1)
                lua.lua_settop(state, -2)
            lua.lua_settop(state, -2)
        if len(rows) < 30000:
            raise RuntimeError('Unexpected localization table schema or incomplete module')
        tables[locale] = rows
        print(locale, 'rows', len(rows))
    finally:
        lua.lua_close(state)

selected = []
if options.find:
    query = re.compile(options.find, re.IGNORECASE)
    for key in sorted(tables['en']):
        row = [key] + [tables[locale][key] for locale in ('en', 'zh_CN', 'zh_TW')]
        if any(query.search(value) for value in row):
            print(json.dumps(row, ensure_ascii=False))
    raise SystemExit(0)
prefixes = ('123900',) if options.item_names else (
    ('101102', '117700') if options.skill_names
    else ('100800', '106801', '105300', '104700')
)
for key, english in tables['en'].items():
    if key.startswith(prefixes):
        selected.append([key, english, tables['zh_CN'].get(key, ''), tables['zh_TW'].get(key, '')])
selected.sort()
target = repo / ('_TranslationWorkspace/item_name_aliases.json' if options.item_names else (
    '_TranslationWorkspace/skill_name_aliases.json' if options.skill_names
    else '_TranslationWorkspace/world_label_aliases.json'
))
target.write_text(json.dumps({'source_sha256': hashes, 'rows': selected}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Exported', 'item-name' if options.item_names else ('skill-name' if options.skill_names else 'world-name'), 'rows:', len(selected), 'to', target)

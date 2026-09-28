"""Codex quiet-test wrapper: installed chat/UI bytecode contracts, no game attachment.
Usage: python scripts/test-chat-contract.py --game-root <launcher directory>
"""
import argparse, subprocess, sys
parser = argparse.ArgumentParser()
parser.add_argument('--game-root', required=True)
parser.add_argument('--worker', action='store_true')
args = parser.parse_args()
if not args.worker:
    result = subprocess.run([sys.executable, __file__, '--game-root', args.game_root, '--worker'], capture_output=True, timeout=30)
    print('Quiet test run: ' + ('PASSED' if result.returncode == 0 else 'FAILED'))
    print('Checks: installed channel enums, chronological history, UI/controller mapping' if result.returncode == 0 else 'FAILED: installed chat contract - scripts/test-chat-contract.py')
    raise SystemExit(result.returncode)

import ctypes as c, os
from pathlib import Path
R = Path(args.game_root)
D = R / 'Client/ro3_Data/Plugins/x86_64'
cookie = os.add_dll_directory(str(D))
x = c.WinDLL(str(D / 'xlua.dll'))
L = c.c_void_p
spec = [('luaL_newstate', L, []), ('luaL_openlibs', None, [L]), ('lua_close', None, [L]), ('luaL_loadbufferx', c.c_int, [L, c.c_char_p, c.c_size_t, c.c_char_p, c.c_char_p]), ('lua_pcall', c.c_int, [L, c.c_int, c.c_int, c.c_int]), ('lua_gettop', c.c_int, [L]), ('lua_settop', None, [L, c.c_int]), ('lua_getglobal', c.c_int, [L, c.c_char_p]), ('lua_setglobal', None, [L, c.c_char_p]), ('lua_getfield', c.c_int, [L, c.c_int, c.c_char_p]), ('lua_setfield', None, [L, c.c_int, c.c_char_p]), ('lua_pushcclosure', None, [L, c.c_void_p, c.c_int]), ('lua_createtable', None, [L, c.c_int, c.c_int]), ('lua_rawgeti', c.c_int, [L, c.c_int, c.c_longlong]), ('lua_pushstring', c.c_char_p, [L, c.c_char_p]), ('lua_settable', None, [L, c.c_int]), ('lua_pushvalue', None, [L, c.c_int]), ('lua_pushinteger', None, [L, c.c_longlong]), ('lua_pushboolean', None, [L, c.c_int]), ('lua_pushnil', None, [L]), ('lua_tolstring', c.c_char_p, [L, c.c_int, c.c_void_p]), ('lua_tointegerx', c.c_longlong, [L, c.c_int, c.c_void_p]), ('lua_toboolean', c.c_int, [L, c.c_int]), ('lua_type', c.c_int, [L, c.c_int])]
for n, r, a in spec:
    f = getattr(x, n)
    f.restype = r
    f.argtypes = a
st = x.luaL_newstate()
x.luaL_openlibs(st)
refs = []

def value(v):
    if callable(v):
        cb = c.CFUNCTYPE(c.c_int, L)(lambda s: v())
        refs.append(cb)
        x.lua_pushcclosure(st, cb, 0)
    elif isinstance(v, dict):
        x.lua_createtable(st, 0, len(v))
        for k, z in v.items():
            value(k)
            value(z)
            x.lua_settable(st, -3)
    elif isinstance(v, str):
        x.lua_pushstring(st, v.encode())
    elif v is None:
        x.lua_pushnil(st)
    elif isinstance(v, bool):
        x.lua_pushboolean(st, int(v))
    else:
        x.lua_pushinteger(st, v)

def ret(v):
    value(v)
    return 1

def glob(k, v):
    value(v)
    x.lua_setglobal(st, k.encode())

def field(i, k):
    x.lua_getfield(st, i, k.encode())
    typ = x.lua_type(st, -1)
    v = x.lua_toboolean(st, -1) if typ == 1 else x.lua_tointegerx(st, -1, None)
    x.lua_settop(st, -2)
    return v

def loadmod(path, name):
    x.lua_settop(st, 0)
    b = (R / ('Client/ro3_Data/StreamingAssets/Recovery/LuaPayload/' + path + '.lua.bytes')).read_bytes()
    assert x.luaL_loadbufferx(st, b, len(b), b'@contract', b'b') == 0
    err=x.lua_pcall(st, 0, 1, 0)
    if err:raise RuntimeError(x.lua_tolstring(st,-1,None))
    x.lua_setglobal(st,name.encode())

glob('BaseClass',lambda:ret({}))
glob('require',lambda:ret({'FriendsChatTimesShow':999999,'SendGetRoleBriefInfoProtoForOnePlayer':lambda:0}))
glob('CS',{'NetworkLib':{'NW_ChatNetworkManager':{'Instance':{}}}})
glob('Lua_DBManager',{'GetInstance':lambda:ret({'m_kCFG_ChatChannelConfig':{'GetMessageLimit':lambda:ret(100)}})})
loadmod('Config/Define/Lua_ChatDefine','Defines')
loadmod('Logic/Chat/LC_ChatHelper','H')
x.lua_getglobal(st,b'H');x.lua_setglobal(st,b'LC_ChatHelper')
def dump(i):
    if i<0:i=x.lua_gettop(st)+i+1
    x.lua_next.restype=c.c_int;x.lua_next.argtypes=[L,c.c_int]
    if x.lua_type(st,i)!=5:
        return x.lua_tolstring(st,i,None) if x.lua_type(st,i) in (3,4) else x.lua_type(st,i)
    result={};x.lua_pushnil(st)
    while x.lua_next(st,i):
        key=x.lua_tolstring(st,-2,None) if x.lua_type(st,-2)==4 else x.lua_tointegerx(st,-2,None)
        result[key]=dump(-1);x.lua_settop(st,-2)
    return result
def asset():
    name=x.lua_tolstring(st,2,None)
    if name==b'AllChannelContent':
        assert x.lua_gettop(st)==2, 'AllChannelContent is read without a nested selector'
        x.lua_getglobal(st,b'H');x.lua_getfield(st,-1,b'm_kAllChannelContent');return 1
    return ret({'id':0})
glob('ServerLocation',{'GetServer':lambda:ret({'GetAssetData':asset,'ExecCmd':lambda:0})})
glob('LC_AssetManager',{})
glob('LC_FriendHelper',{'CheckIsAlreadyBlack':lambda:ret(False)})
glob('LC_Event',{'DispatchEvent':lambda:0})
glob('LC_ModuleId',{'Common':1})
glob('LC_NotifyId',{'Common':{}})
glob('TimerManager',{'GetInstance':lambda:ret({'GetSystemTime':lambda:ret(1000)})})
glob('LC_ChatMessageHandler',{'GenTimeStampExtraParam':lambda:ret({}),'ParseExtraParam':lambda:ret({})})
glob('enum_AssetManager_Cmd',{'Replace':1})
x.lua_getglobal(st,b'H');value(lambda:ret({'message_id':'time','send_time':0,'extra_param':{'eMessageType':8,'iChannelIndex':8,'eChatType':2}}));x.lua_setfield(st,-2,b'CreateMessage');x.lua_settop(st,0)
for mid,time in [('m2',200),('m1',100),('m3',300)]:
    msg={'message_id':mid,'send_time':time,'extra_param':{'iChannelIndex':8,'eChatType':2},'receive_id':'recruit','sender_id':'1'}
    x.lua_settop(st,0);x.lua_getglobal(st,b'H');x.lua_getfield(st,-1,b'SaveAllChannelContent');value(msg)
    err=x.lua_pcall(st,1,0,0);assert err == 0, x.lua_tolstring(st,-1,None)
x.lua_settop(st,0);x.lua_getglobal(st,b'H');x.lua_getfield(st,-1,b'm_kAllChannelContent')
channel = dump(-1)[b'recruit']
assert channel[b'index'] == b'8' and channel[b'channelType'] == b'2'
rows = channel[b'data']
assert [rows[i][b'message_id'] for i in range(1,5)] == [b'time', b'm1', b'm2', b'm3']
assert rows[1][b'extra_param'][b'eMessageType'] == b'8'
for enum, key, expected in [('enum_EPublicChatChannelType','EChannelRecruit',8), ('enum_SendMsgType','ChannelChat',2), ('enum_ChatSpecialContent','TimeStamp',8)]:
    x.lua_settop(st,0);x.lua_getglobal(st,enum.encode());assert field(-1,key)==expected


loadmod('UI/Lua_UIBase','U')
glob('Lua_UT_Helper',{'SetActive':lambda:0})

glob('C',{'m_iUIIndex':17,'GetUIIndex':lambda:ret(17),'View':{'OnOpen':lambda:0},'SetUpdateEnable':lambda:0,'_onTryDispatchGuideOpenViewEvent':lambda:0,'_onRegisterPipeline':lambda:0,'m_bInitActive':True,'gameObject':'owner'})
x.lua_settop(st,0);x.lua_getglobal(st,b'C');x.lua_getglobal(st,b'U');x.lua_getfield(st,-1,b'm_kUIMap');x.lua_setfield(st,1,b'm_kUIMap');x.lua_settop(st,0)
x.lua_getglobal(st,b'U');x.lua_getfield(st,-1,b'OnOpen');x.lua_getglobal(st,b'C');err=x.lua_pcall(st,1,0,0);assert err==0,x.lua_tolstring(st,-1,None)
x.lua_settop(st,0);x.lua_getglobal(st,b'U');x.lua_getfield(st,-1,b'm_kUIMap');x.lua_rawgeti(st,-1,17);assert x.lua_type(st,-1)==5;x.lua_getfield(st,-1,b'gameObject');assert x.lua_tolstring(st,-1,None)==b'owner'
x.lua_close(st)

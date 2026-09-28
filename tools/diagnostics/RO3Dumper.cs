using System;
using System.IO;
using System.Reflection;

public static class RO3Dumper {
    private static bool _dumped = false;

    public static void TryDump() {
        if (_dumped) return;
        try {
            Type laType = null;
            foreach (Assembly asm in AppDomain.CurrentDomain.GetAssemblies()) {
                if (asm.GetName().Name == "Assembly-CSharp") {
                    laType = asm.GetType("LA_LuaManager");
                    break;
                }
            }
            if (laType == null) return;

            PropertyInfo instProp = laType.BaseType.GetProperty("Instance");
            if (instProp == null) return;
            object inst = instProp.GetValue(null, null);
            if (inst == null) return;

            MethodInfo obfKd = laType.GetMethod("Obf_KD");
            if (obfKd == null) return;

            string luaCode = @"
local function do_dump(modname, path)
    local t = package.loaded[modname]
    if not t then pcall(function() t = require(modname) end) end
    if not t then return 'missing ' .. modname end
    local f = io and io.open and io.open(path, 'w')
    if f then
        for k, v in pairs(t) do
            if type(v) == 'string' then
                f:write(tostring(k) .. '\t' .. v:gsub('\r', ''):gsub('\n', '\\n') .. '\n')
            end
        end
        f:close()
        return 'io.open ok: ' .. path
    elseif CS and CS.System and CS.System.IO then
        local sb = CS.System.Text.StringBuilder()
        for k, v in pairs(t) do
            if type(v) == 'string' then
                sb:Append(tostring(k)):Append('\t'):Append(v:gsub('\r', ''):gsub('\n', '\\n')):Append('\n')
            end
        end
        CS.System.IO.File.WriteAllText(path, sb:ToString())
        return 'CS.System.IO ok: ' .. path
    end
    return 'no writer available'
end

local r1 = do_dump('Localization_en', 'C:/Path/To/RO3 Asia Launcher/_TranslationWorkspace/dump_loc_en.tsv')
local r2 = do_dump('Localization_zh_CN', 'C:/Path/To/RO3 Asia Launcher/_TranslationWorkspace/dump_loc_zh.tsv')
return r1 .. ' | ' .. r2
";

            object[] res = (object[])obfKd.Invoke(inst, new object[] { luaCode });
            _dumped = true;
            string status = (res != null && res.Length > 0 && res[0] != null) ? res[0].ToString() : "no return";
            File.WriteAllText(@"C:\Path\To\RO3 Asia Launcher\_TranslationWorkspace\dump_status.txt", "Dump success! " + status);
        } catch (Exception ex) {
            File.WriteAllText(@"C:\Path\To\RO3 Asia Launcher\_TranslationWorkspace\dump_error.txt", ex.ToString());
        }
    }
}
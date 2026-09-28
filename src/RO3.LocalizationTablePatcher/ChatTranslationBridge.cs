using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;
using UnityEngine;
using HarmonyLib;

namespace RO3.JapaneseMod
{
    public sealed partial class LocalizationTablePatcherPlugin
    {
        private sealed class ChatBinding
        {
            internal object Controller;
            internal object Index;
        }

        private static object _chatLuaEnv;
        private static object _chatUiMap;
        private static object _chatChannels;
        private static int _chatHistoryFrame = -1;
        private static ChatTranslationPolicy _chatPolicy = new ChatTranslationPolicy();
        private static ConditionalWeakTable<Component, ChatBinding> _chatBindings = new ConditionalWeakTable<Component, ChatBinding>();
        private static readonly Dictionary<GameObject, ChatBinding> _chatControllers = new Dictionary<GameObject, ChatBinding>();
        private static bool _chatMetadataLogged;
        private static DateTime _nextChatEnvLookup;
        private static int _chatMissingMetadata;

        private void InstallChatMetadataHook()
        {
            Type manager = FindType("LA_LuaManager");
            MethodInfo getter = manager == null ? null : manager.GetMethod("Obf_jD", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
            if (getter == null)
            {
                _displayLog.LogWarning("[Chat] Lua environment getter unavailable; chat translation will stay disabled.");
                return;
            }
            // Keep this with the display hooks: the game destroys the plugin's
            // Unity component and removes its separate lifecycle hooks at boot.
            _displayHarmony.Patch(getter, postfix: new HarmonyMethod(typeof(LocalizationTablePatcherPlugin).GetMethod("ChatLuaEnvPostfix", BindingFlags.Static | BindingFlags.NonPublic)));
        }

        private static void ChatLuaEnvPostfix(object __result)
        {
            if (__result == null || ReferenceEquals(__result, _chatLuaEnv)) return;
            _chatLuaEnv = __result;
            _chatUiMap = null;
            _chatChannels = null;
            _chatHistoryFrame = -1;
            _chatControllers.Clear();
            _chatBindings = new ConditionalWeakTable<Component, ChatBinding>();
            _chatPolicy = new ChatTranslationPolicy();
        }

        private static ChatBinding FindChatBinding(Component component)
        {
            if (_chatLuaEnv == null && DateTime.UtcNow >= _nextChatEnvLookup)
            {
                _nextChatEnvLookup = DateTime.UtcNow.AddSeconds(1);
                // Read an existing manager only; its singleton getter would
                // create one prematurely during the game's bootstrap.
                foreach (Type type in FindTypes("LA_LuaManager"))
                {
                    UnityEngine.Object manager = UnityEngine.Object.FindObjectOfType(type);
                    if (manager == null) continue;
                    ChatLuaEnvPostfix(GetInstanceField(manager, type, "Obf_Dc"));
                    if (_chatLuaEnv != null) break;
                }
            }
            if (_chatUiMap == null)
                _chatUiMap = GetLuaTableStringValue(GetGlobalTableFromLuaEnv(_chatLuaEnv, "UIBase"), "m_kUIMap");
            if (_chatUiMap == null) return null;
            ChatBinding binding;
            if (_chatBindings.TryGetValue(component, out binding))
            {
                // Pooled widgets may acquire a new controller without replacing
                // their TMP component. Never retain the old channel decision.
                if (System.Object.Equals(ChatTranslationPolicy.At(_chatUiMap, binding.Index), binding.Controller)) return binding;
                _chatBindings.Remove(component);
            }
            for (int pass = 0; pass < 2; pass++)
            {
                for (Transform node = component.transform; node != null; node = node.parent)
                {
                    if (!_chatControllers.TryGetValue(node.gameObject, out binding)) continue;
                    if (!System.Object.Equals(ChatTranslationPolicy.At(_chatUiMap, binding.Index), binding.Controller)) continue;
                    _chatBindings.Add(component, binding);
                    return binding;
                }
                if (pass != 0) break;
                // Rebuild only on a new/unbound widget, including controllers
                // whose SetData has not run yet. Rows can open in one frame.
                _chatControllers.Clear();
                foreach (object key in EnumerateLuaTableKeys(_chatUiMap, 4096))
                {
                    object controller = GetLuaTableObjectValue(_chatUiMap, key);
                    GameObject owner = GetLuaTableStringValue(controller, "gameObject") as GameObject;
                    if (owner != null && ChatDisplayGate.IsChatMessagePath(new[] { owner.name }))
                        _chatControllers[owner] = new ChatBinding { Controller = controller, Index = key };
                }
            }
            return null;
        }

        private static string TranslateChatDisplay(Component component, string input)
        {
            ChatBinding binding = FindChatBinding(component);
            if (binding == null)
            {
                if (++_chatMissingMetadata == 100)
                    _displayLog.LogWarning("[Chat] Message metadata is not ready; retaining original chat text until it is available.");
                return input; // unknown metadata must not translate the whole history
            }
            object data = GetLuaTableStringValue(binding.Controller, "m_kData");
            if (!ChatTranslationPolicy.IsRecruitment(data)) return input;
            if (_chatHistoryFrame != Time.frameCount)
            {
                _chatHistoryFrame = Time.frameCount;
                object location = GetGlobalTableFromLuaEnv(_chatLuaEnv, "ServerLocation");
                object asset = CallChatLua(location, "GetServer", location, "LC_AssetManager");
                _chatChannels = CallChatLua(asset, "GetAssetData", asset, "AllChannelContent");
                if (_chatChannels == null)
                    _chatChannels = GetLuaTableStringValue(GetGlobalTableFromLuaEnv(_chatLuaEnv, "LC_ChatHelper"), "m_kAllChannelContent");
            }
            object channel = GetLuaTableObjectValue(_chatChannels, GetLuaTableStringValue(data, "receive_id"));
            object history = GetLuaTableStringValue(channel, "data");
            if (history == null) return input;
            if (!_chatMetadataLogged)
            {
                _chatMetadataLogged = true;
                _displayLog.LogInfo("[Chat] Recruitment channel metadata connected; latest 10 messages, cached local translations only.");
            }
            return _chatPolicy.Translate(data, history, input, _displayTranslator.Translate);
        }

        private static object CallChatLua(object table, string method, params object[] args)
        {
            object function = GetLuaTableStringValue(table, method);
            if (function == null) return null;
            MethodInfo call = function.GetType().GetMethod("Obf_HuA", new[] { typeof(object[]) });
            if (call == null) return null;
            object[] result = call.Invoke(function, new object[] { args }) as object[];
            return result == null || result.Length == 0 ? null : result[0];
        }
    }
}

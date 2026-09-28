using System;
using System.Collections.Generic;
using System.Globalization;
using System.Reflection;

namespace RO3.JapaneseMod
{
    // Reads the existing Lua tables; never edits message/history data.
    internal sealed class ChatTranslationPolicy
    {
        internal const int HistoryLimit = 10;
        internal const int CacheLimit = 256;
        private readonly Dictionary<string, string> translations = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Queue<string> insertionOrder = new Queue<string>();
        internal static object Field(object table, string key)
        {
            if (table == null) return null;
            MethodInfo get = table.GetType().GetMethod("Obf_MuA", new[] { typeof(string) });
            return get == null ? null : get.Invoke(table, new object[] { key });
        }

        internal static object At(object table, object key)
        {
            if (table == null || key == null) return null;
            MethodInfo get = table.GetType().GetMethod("Obf_NuA", new[] { typeof(object) });
            return get == null ? null : get.Invoke(table, new[] { key });
        }

        internal static string Id(object message)
        {
            object id = Field(message, "message_id");
            return id == null ? null : Convert.ToString(id, CultureInfo.InvariantCulture);
        }

        internal static bool IsRecruitment(object message)
        {
            object extra = Field(message, "extra_param");
            // Verified against the installed Lua_ChatDefine, not UI labels.
            return Convert.ToString(Field(extra, "iChannelIndex"), CultureInfo.InvariantCulture) == "8"
                && Convert.ToString(Field(extra, "eChatType"), CultureInfo.InvariantCulture) == "2"
                && Convert.ToString(Field(extra, "eMessageType"), CultureInfo.InvariantCulture) != "8";
        }

        internal string Translate(object message, object history, string text, Func<string, string> translate)
        {
            if (String.IsNullOrEmpty(text) || !IsRecruitment(message) || history == null) return text;
            string id = Id(message);
            if (String.IsNullOrEmpty(id)) return text;
            MethodInfo length = history.GetType().GetMethod("Obf_puA", Type.EmptyTypes);
            if (length == null) return text;
            int count = Convert.ToInt32(length.Invoke(history, null), CultureInfo.InvariantCulture);
            // Read only the tail window. Re-check it even when length/last ID
            // are unchanged: out-of-order arrivals can change a full list.
            bool allowed = false;
            int messages = 0;
            for (int i = count; i > 0 && messages < HistoryLimit; i--)
            {
                object row = At(history, i);
                if (!IsRecruitment(row)) continue;
                string rowId = Id(row);
                if (String.IsNullOrEmpty(rowId)) continue;
                messages++;
                if (rowId == id) { allowed = true; break; }
            }
            if (!allowed) return text;
            string result;
            if (translations.TryGetValue(text, out result)) return result;
            result = translate(text) ?? text;
            Remember(text, result);
            // TMP's render hook sees the already-translated backing text next.
            Remember(result, result);
            return result;
        }

        private void Remember(string text, string result)
        {
            if (translations.ContainsKey(text)) return;
            if (translations.Count >= CacheLimit) translations.Remove(insertionOrder.Dequeue());
            translations.Add(text, result);
            insertionOrder.Enqueue(text);
        }
    }
}

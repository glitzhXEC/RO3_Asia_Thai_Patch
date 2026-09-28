using System;
using System.Collections.Generic;
using RO3.JapaneseMod;

// Match the installed XLua table access contract, including 1-based indexing.
class ChatTable
{
    public Dictionary<string, object> Fields = new Dictionary<string, object>();
    public List<object> Rows = new List<object>();
    public object Obf_MuA(string key) { object value; return Fields.TryGetValue(key, out value) ? value : null; }
    public object Obf_NuA(object key) { int i = Convert.ToInt32(key); return i > 0 && i <= Rows.Count ? Rows[i - 1] : null; }
    public int Obf_puA() { return Rows.Count; }
}

class ChatTranslationPolicyTest
{
    static int total, failed;
    static void Check(bool condition, string name)
    {
        total++;
        if (!condition) { failed++; Console.WriteLine("FAILED: " + name); }
    }
    static ChatTable Message(int id, int channel, int kind)
    {
        var extra = new ChatTable();
        extra.Fields["iChannelIndex"] = channel;
        extra.Fields["eChatType"] = 2;
        extra.Fields["eMessageType"] = kind;
        var msg = new ChatTable();
        msg.Fields["message_id"] = id.ToString();
        msg.Fields["extra_param"] = extra;
        return msg;
    }
    public static int Main()
    {
        var policy = new ChatTranslationPolicy();
        var history = new ChatTable();
        int calls = 0;
        Func<string, string> translate = delegate(string s) { calls++; return "JA:" + s; };
        for (int i = 1; i <= 30; i++) {
            history.Rows.Add(Message(i, 8, 2));
            history.Rows.Add(Message(1000 + i, 8, 8)); // interleaved time labels
        }
        for (int i = 1; i <= 30; i++) {
            var m = history.Rows[(i - 1) * 2];
            Check(policy.Translate(m, history, "body" + i, translate) == (i > 20 ? "JA:" : "") + "body" + i, "history boundary " + i);
        }
        Check(calls == 10, "only ten translator calls for thirty messages");
        for (int i = 1; i <= 30; i++) policy.Translate(history.Rows[(i - 1) * 2], history, "body" + i, translate);
        Check(calls == 10, "reopen and render do not translate again");
        var live = Message(31, 8, 2);
        history.Rows.RemoveRange(0, 2);
        history.Rows.Add(live);
        history.Rows.Add(Message(1031, 8, 8));
        Check(policy.Translate(live, history, "new", translate) == "JA:new", "live message with same history length");
        Check(calls == 11, "live message translates once");
        Check(policy.Translate(live, history, "JA:new", translate) == "JA:new" && calls == 11, "rendering translated backing text is free");
        var outOfOrder = Message(35, 8, 2);
        history.Rows[history.Rows.Count - 4] = outOfOrder;
        Check(policy.Translate(outOfOrder, history, "new", translate) == "JA:new", "out of order insertion with same length and tail ID");
        var other = Message(32, 1, 2);
        Check(policy.Translate(other, history, "body30", translate) == "body30", "world channel bypasses even cached text");
        ((ChatTable)other.Fields["extra_param"]).Fields["iChannelIndex"] = 8;
        ((ChatTable)other.Fields["extra_param"]).Fields["eChatType"] = 1;
        Check(policy.Translate(other, history, "private", translate) == "private", "private chat never inherits channel permission");
        Check(policy.Translate(null, history, "unknown", translate) == "unknown", "missing message fails closed");
        Check(policy.Translate(live, null, "unknown", translate) == "unknown", "missing history fails closed");
        Check(calls == 11, "bypassed cases cost no translations");
        Check(policy.Translate(live, history, "changed members", translate) == "JA:changed members", "changed recruitment card invalidates cached text");
        var sameLengthReload = new ChatTable(); sameLengthReload.Rows.Add(Message(99, 8, 2));
        Check(policy.Translate(live, sameLengthReload, "new", translate) == "new", "new history does not reuse old allowed IDs");
        var blankId = Message(1, 8, 2); blankId.Fields.Remove("message_id");
        Check(policy.Translate(blankId, history, "bad", translate) == "bad", "missing ID bypasses");
        var shortHistory = new ChatTable(); shortHistory.Rows.Add(live);
        Check(policy.Translate(live, shortHistory, "new", translate) == "JA:new", "fewer than ten messages allowed");
        for (int i = 0; i < 300; i++) policy.Translate(live, shortHistory, "cache" + i, translate);
        int before = calls;
        policy.Translate(live, shortHistory, "cache299", translate);
        Check(calls == before, "newest cached entry retained");
        policy.Translate(live, shortHistory, "cache0", translate);
        Check(calls == before + 1, "bounded cache evicts oldest entry");
        Console.WriteLine("Tests: " + (total - failed) + "/" + total + " passed");
        return failed == 0 ? 0 : 1;
    }
}

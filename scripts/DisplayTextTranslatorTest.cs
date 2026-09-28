using System;
using System.IO;
using RO3.JapaneseMod;

class DisplayTextTranslatorTest
{
    class GetterTranslatedText
    {
        private string m_text;
        public GetterTranslatedText(string raw) { m_text = raw; }
        public string text { get { return "Getter already translated"; } }
    }
    class BufferedText : GetterTranslatedText
    {
        private bool m_IsTextBackingStringDirty;
        private readonly string buffer;
        public BufferedText(string raw, string current, bool dirty) : base(raw)
        { buffer = current; m_IsTextBackingStringDirty = dirty; }
        private string InternalTextBackingArrayToString() { return buffer; }
    }
    class LegacyText
    {
        private string m_Text = "Legacy raw";
        public string text { get { return "Getter already translated"; } }
    }
    class OtherText { public string text { get { return "Fallback raw"; } } }

    static int Main(string[] args)
    {
        var translator = new DisplayTextTranslator();
        foreach (string line in File.ReadAllLines(args[0]))
        {
            string[] fields = line.TrimStart('\uFEFF').Split(new[] { '\t' }, 3);
            if (fields.Length == 3) translator.Add(fields[0], fields[1], fields[2]);
        }
        foreach (string line in File.ReadAllLines(args[1]))
        {
            string[] fields = line.TrimStart('\uFEFF').Split(new[] { '\t' }, 3);
            if (fields.Length == 3 && !fields[0].StartsWith("#")) translator.Add(fields[0], fields[1], fields[2]);
        }
        string[,] cases = {
            { "嘉酷Biubiubiu: Discover a great item! Come check it out! [Mink Coat]", "嘉酷Biubiubiu: すごいアイテムを見つけた！見に来て！ [ミンクのコート]" },
            { "<#d5b376><nlink=openplayerInfo/12345>TestPlayer</nlink>:</color>I Discover a great item! Come check it out! <color=#FDAB5B><u><link=\"item/67890\">[Mink Coat]</link></u></color>", "<#d5b376><nlink=openplayerInfo/12345>TestPlayer</nlink>:</color>すごいアイテムを見つけた！見に来て！ <color=#FDAB5B><u><link=\"item/67890\">[ミンクのコート]</link></u></color>" },
            { "I Discover a great item! Come check it out! [Mink Coat]", "すごいアイテムを見つけた！見に来て！ [ミンクのコート]" },
            { "TestPlayer: すごいアイテムを見つけた！見に来て！<color=#FDAB5B><u><link=\"item/67890\">[Mink Coat]</link></u></color>", "TestPlayer: すごいアイテムを見つけた！見に来て！<color=#FDAB5B><u><link=\"item/67890\">[ミンクのコート]</link></u></color>" },
            { "TestPlayer: Discover a great item! Come check it out! [Unknown Item]", "TestPlayer: Discover a great item! Come check it out! [Unknown Item]" },
            { "TestPlayer: Discover a great item! Come check it out! is my slogan [Mink Coat]", "TestPlayer: Discover a great item! Come check it out! is my slogan [Mink Coat]" },
            { "紅辣椒", "赤唐辛子" },
            { "红辣椒", "赤唐辛子" },
            { "紅色藥草", "赤ハーブ" },
            { "红色药草", "赤ハーブ" },
            { "高阶治愈术", "ハイネスヒール" },
            { "高階治癒術", "ハイネスヒール" },
            { "奉献颂歌", "献身の賛歌" },
            { "奉獻頌歌", "献身の賛歌" },
            { "灿烂圣光", "輝けるホーリーライト" },
            { "燦爛聖光", "輝けるホーリーライト" },
            { "复活术", "リザレクション" },
            { "復活術", "リザレクション" },
            { "霸邪之阵", "キリエエレイソン" },
            { "霸邪之陣", "キリエエレイソン" },
            { "技能队列", "スキルバー" },
            { "技能隊列", "スキルバー" },
            { "技能队列Lv.1", "スキルバーLv.1" },
            { "技能隊列 Lv.10", "スキルバー Lv.10" },
            { "Skill Bar Lv.2", "スキルバー Lv.2" },
            { "<color=#ffce63>技能队列Lv.1</color>", "<color=#ffce63>スキルバーLv.1</color>" },
            { "TestPlayer:技能队列Lv.1", "TestPlayer:技能队列Lv.1" },
            { "<color=#ffce63>高階治癒術</color>", "<color=#ffce63>ハイネスヒール</color>" },
            { "TestPlayer:高階治癒術", "TestPlayer:高階治癒術" },
            { "Goblin Archer", "ゴブリンアーチャー" },
            { "プレイヤー【TestPlayer】が【Eddga】を撃破し、レア報酬を獲得しました！", "プレイヤー【TestPlayer】が【エドガ】を撃破し、レア報酬を獲得しました！" },
            { "Moonlight FlowerはTestPlayerに倒されました。", "月夜花はTestPlayerに倒されました。" },
            { "Moonlight Flower was defeated by TestPlayer.", "月夜花はTestPlayerに倒されました。" },
            { "<color=#fdab5b>Moonlight Flower</color>は<color=#fdab5b>TestPlayer</color>に倒されました。", "<color=#fdab5b>月夜花</color>は<color=#fdab5b>TestPlayer</color>に倒されました。" },
            { "EddgaはUnlistedPlayerに倒されました。", "エドガはUnlistedPlayerに倒されました。" },
            { "UnlistedBossはEddgaに倒されました。", "UnlistedBossはEddgaに倒されました。" },
            { "<color=#6890D2>Earrings</color> X 1を自動解体し、<color=#6890D2>Minted Coin</color> X 50を獲得しました。", "<color=#6890D2>イヤリング</color> X 1を自動解体し、<color=#6890D2>鋳造されたコイン</color> X 50を獲得しました。" },
            { "Automatically dismantled <color=#62AF5E>Rod</color> X 1 and obtained <color=#6890D2>Minted Coin</color> X 5.", "<color=#62AF5E>ロッド</color> X 1を自動解体し、<color=#6890D2>鋳造されたコイン</color> X 5を獲得しました。" },
            { "UnlistedItem X 1を自動解体し、Minted Coin X 50を獲得しました。", "UnlistedItem X 1を自動解体し、鋳造されたコイン X 50を獲得しました。" },
            { "Successfully dismantled <color=#62AF5E>Ring</color> X 1 and obtained <color=#6890D2>Minted Coin</color> X 5.", "<color=#62AF5E>リング</color> X 1を解体し、<color=#6890D2>鋳造されたコイン</color> X 5を獲得しました。" },
            { "<color=#62AF5E>Sandals</color> X 1を解体し、<color=#6890D2>Minted Coin</color> X 5を獲得しました。", "<color=#62AF5E>サンダル</color> X 1を解体し、<color=#6890D2>鋳造されたコイン</color> X 5を獲得しました。" },
            { "Combine is successful. Obtained <color=#62AF5E>Ring</color> X 1.", "合成成功。<color=#62AF5E>リング</color> X 1を獲得しました。" },
            { "合成成功。<color=#62AF5E>Ring</color> X 1を獲得しました。", "合成成功。<color=#62AF5E>リング</color> X 1を獲得しました。" },
            { "Obtained <color=#6890D2>Minted Coin</color> X 50", "<color=#6890D2>鋳造されたコイン</color> X 50 を獲得" },
            { "<color=#6890D2>Minted Coin</color> X 50 を獲得", "<color=#6890D2>鋳造されたコイン</color> X 50 を獲得" },
            { "プレイヤー【<color=#fdab5b>TestPlayer</color>】が【<color=#fdab5b>Eddga</color>】を撃破し、レア報酬を獲得しました！", "プレイヤー【<color=#fdab5b>TestPlayer</color>】が【<color=#fdab5b>エドガ</color>】を撃破し、レア報酬を獲得しました！" },
            { "Congratulations to player 【TestPlayer】 for defeating 【Baphomet】 and earning a Rare reward!", "プレイヤー【TestPlayer】が【バフォメット】を撃破し、レア報酬を獲得しました！" },
            { "Congratulations to player 【<color=#fdab5b>TestPlayer</color>】 for defeating 【<color=#fdab5b>Eddga</color>】 and earning a Rare reward!", "プレイヤー【<color=#fdab5b>TestPlayer</color>】が【<color=#fdab5b>エドガ</color>】を撃破し、レア報酬を獲得しました！" },
            { "プレイヤー【Eddga】が【UnlistedBoss】を撃破し、レア報酬を獲得しました！", "プレイヤー【Eddga】が【UnlistedBoss】を撃破し、レア報酬を獲得しました！" },
            { "Magnus Exorcismus!!", "マグヌスエクソシズム!!" },
            { "Take part in events and enjoy your adventures in this world", "イベントに参加して、この世界での冒険を楽しもう" },
            { "<color=#FF0000>Goblin Archer</color>", "<color=#FF0000>ゴブリンアーチャー</color>" },
            { "Current Server Level Cap: Lv. 69\n09/24/2026 05:00:00: Server Level Cap increases to Lv. 79", "現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00：サーバーレベル上限がLv.79に上昇" },
            { "<color=#99FF9F>Current Server Level Cap: Lv. 69\n09/24/2026 05:00:00: Server Level Cap increases to Lv. 79</color>", "<color=#99FF9F>現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00：サーバーレベル上限がLv.79に上昇</color>" },
            { "Monsters Unlocked: 136/162", "解放モンスター：136/162" },
            { "Dedicated Scholar-2", "熱心な学者-2" },
            { "Complete the Commission: 0/1", "依頼を完了：0/1" },
            { "[Commission] Defeat Monsters (2/10)", "[依頼] モンスター討伐（2/10）" },
            { "<color=#ec8c2f>[Commission]</color> Defeat Monsters (2/10)", "<color=#ec8c2f>[依頼]</color> モンスター討伐（2/10）" },
            { "Geffen Outskirtsでモンスターを討伐：0/20", "ゲフェン郊外でモンスターを討伐：0/20" },
            { "Geffen Outskirtsで待ち合わせ", "Geffen Outskirtsで待ち合わせ" },
            { "Unknown Placeでモンスターを討伐：0/20", "Unknown Placeでモンスターを討伐：0/20" },
            { "Gardener 経験 +270 (51930/55000)", "園芸師 経験 +270 (51930/55000)" },
            { "Miner 経験 +30 (10/100)", "採掘師 経験 +30 (10/100)" },
            { "<color=#cccccc>Chef</color> 経験 +20 (3/100)", "<color=#cccccc>調理師</color> 経験 +20 (3/100)" },
            { "Gardenerとの会話 +270 (51930/55000)", "Gardenerとの会話 +270 (51930/55000)" },
            { "Kill MVPs: 0/5", "MVP討伐数: 0/5" },
            { "Join the Caravan: 0/1", "キャラバンに参加：0/1" },
            { "High-Reward Auto Mode: 60/60", "高報酬オートモード: 60/60" },
            { "Consume Vigor: 0/100", "活力消費：0/100" },
            { "Take on a squad Challenge against the Phantom Realm BOSS with 5 players to earn tons of rewards.", "5人でファントムレルムBOSSに挑むチームチャレンジに参加し、大量の報酬を獲得しましょう。" },
            { "Take on a Party Challenge against the Realm of the Gods BOSS with 10 players to earn tons of rewards.", "10人で神域BOSSに挑むパーティチャレンジに参加し、大量の報酬を獲得しましょう。" },
            { "Consumed when gathering and crafting with a Life Skill. Obtain it from Recommend-Activity Chests. You can accumulate up to 5000 points.", "生活スキルでの採取や製作時に消費される。おすすめアクティビティ宝箱から入手可能。最大5000ポイントまで累積できる。" },
            { "Consumed when gathering and crafting with a Life Skill. Obtain it from Recommend-Activity Chests. You can accumulate up to <color=#ff993f>5000</color> points.", "生活スキルでの採取や製作時に消費される。おすすめアクティビティ宝箱から入手可能。最大<color=#ff993f>5000</color>ポイントまで累積できる。" },
            { "A vibrant Green Healing Potion that instantly restores 1500 HP. Cooldown: 40 sec.", "鮮やかな緑の回復ポーション。HPを即座に1500回復。クールダウン：40秒。" },
            { "MATK +22", "魔法攻撃 +22" },
            { "Magic Damage Increase +0.23%", "魔法ダメージ増加 +0.23%" },
            { "MATK Increase", "MATK増加" },
            { "mikosurihan", "mikosurihan" },
            { "ゴブリンアーチャー", "ゴブリンアーチャー" },
            { "Current Server Level Cap: unexpected format", "Current Server Level Cap: unexpected format" },
            { "Take part in events and enjoy your adventures in this world\n<color=#99FF9F>Current Server Level Cap: Lv. 69\n09/24/2026 05:00:00: サーバーレベル上限がLv.79に上昇</color>", "イベントに参加して、この世界での冒険を楽しもう\n<color=#99FF9F>現在のサーバーレベル上限：Lv.69\n09/24/2026 05:00:00: サーバーレベル上限がLv.79に上昇</color>" },
            { "", "" },
            { null, null }
        };
        int failed = 0;
        for (int i = 0; i < cases.GetLength(0); i++)
        {
            string actual = translator.Translate(cases[i, 0]);
            if (actual != cases[i, 1] || translator.Translate(actual) != actual)
            {
                Console.WriteLine("FAILED: display case " + i);
                failed++;
            }
        }
        string[,] backingCases = {
            { DisplayTextBackingStore.Read(new GetterTranslatedText("Goblin Archer")), "Goblin Archer" },
            { DisplayTextBackingStore.Read(new GetterTranslatedText("Second instance")), "Second instance" },
            { DisplayTextBackingStore.Read(new BufferedText("Stale", "Current buffer", true)), "Current buffer" },
            { DisplayTextBackingStore.Read(new BufferedText("Current string", "Stale buffer", false)), "Current string" },
            { DisplayTextBackingStore.Read(new BufferedText("Stale", "", true)), "" },
            { DisplayTextBackingStore.Read(new LegacyText()), "Legacy raw" },
            { DisplayTextBackingStore.Read(new OtherText()), "Fallback raw" },
            { DisplayTextBackingStore.Read(null), null },
        };
        for (int i = 0; i < backingCases.GetLength(0); i++)
            if (backingCases[i, 0] != backingCases[i, 1]) { Console.WriteLine("FAILED: backing text case " + i); failed++; }
        translator.AddOfflineExact("None", "なし");
        string[] rankPath = { "Team_TTxt", "TeamType_TTxt", "Layout_Info", "Info", "Top_GraphicSwitchG", "TipsRoot_RTransform" };
        string[,] rankCases = {
            { "无", "なし" }, { "無", "なし" },
            { "<color=#7e7361>无</color>", "<color=#7e7361>なし</color>" },
            { "无題", "无題" }, { "TestPlayer", "TestPlayer" }, { "なし", "なし" },
        };
        for (int i = 0; i < rankCases.GetLength(0); i++)
            if (translator.TranslateProfileRankValue(rankCases[i, 0], rankPath) != rankCases[i, 1])
            { Console.WriteLine("FAILED: scoped rank case " + i); failed++; }
        for (int i = 0; i < rankPath.Length; i++)
        {
            string[] otherSlot = (string[])rankPath.Clone();
            otherSlot[i] = "OtherField";
            if (translator.TranslateProfileRankValue("无", otherSlot) != "无")
            { Console.WriteLine("FAILED: unrelated rank slot " + i); failed++; }
        }
        string[][] chatPaths = {
            new[] { "ChatText_TTxt", "Pan_Cell", "UI_Sys_Main_ChatWidget_PC(Clone)" },
            new[] { "ChatText_TTxt", "UI_Sys_Chat_MineNewWidget(Clone)" },
            new[] { "ChatText_TTxt", "UI_Sys_Chat_OtherNewWidget(Clone)" },
            new[] { "Text_TTxt", "UI_Sys_Friend_ChatListLeftWidget_PC(Clone)" },
            new[] { "Text_TTxt", "UI_Sys_Friend_ChatListRightWidget_PC(Clone)" },
        };
        for (int i = 0; i < chatPaths.Length; i++)
            if (!ChatDisplayGate.IsChatMessagePath(chatPaths[i]))
            { Console.WriteLine("FAILED: chat path " + i); failed++; }
        string[][] nonChatPaths = {
            new[] { "ChannelName_TTxt", "Pan_Cell", "UI_Sys_Chat_ChannelListWidget(Clone)", "Chat_LoopList" },
            new[] { "Title_TTxt", "Header", "UI_Sys_Chat_SmallWindowPanel" },
            new[] { "InputText", "Chat_InputField", "UI_Sys_Chat_SmallWindow_Content_Widget(Clone)" },
            new[] { "ItemText_TTxt", "Pan_Cell", "UI_Sys_Shop_LoopList" },
            new[] { "FPS_TTxt", "HUD", "UIRoot" },
        };
        for (int i = 0; i < nonChatPaths.Length; i++)
            if (ChatDisplayGate.IsChatMessagePath(nonChatPaths[i]))
            { Console.WriteLine("FAILED: non-chat path " + i); failed++; }
        int total = cases.GetLength(0) + backingCases.GetLength(0) + rankCases.GetLength(0) + rankPath.Length
            + chatPaths.Length + nonChatPaths.Length;
        Console.WriteLine("Tests: " + (total - failed) + "/" + total + " passed");
        return failed == 0 ? 0 : 1;
    }
}

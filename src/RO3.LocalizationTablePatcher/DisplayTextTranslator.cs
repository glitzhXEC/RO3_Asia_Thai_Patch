using System;
using System.Collections.Generic;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace RO3.JapaneseMod
{
    // Getter compatibility hooks may return Japanese while TMP still holds an
    // English string/character buffer. Compare against the real backing value
    // before deciding whether a serialized or pre-render label needs writing.
    internal static class DisplayTextBackingStore
    {
        private sealed class Access
        {
            public FieldInfo Text, Dirty;
            public MethodInfo BufferToString;
            public PropertyInfo Fallback;
        }

        private static readonly Dictionary<Type, Access> Readers = new Dictionary<Type, Access>();

        public static string Read(object instance)
        {
            if (instance == null) return null;
            Type type = instance.GetType();
            Access access;
            lock (Readers)
            {
                if (!Readers.TryGetValue(type, out access))
                {
                    access = new Access();
                    for (Type current = type; current != null; current = current.BaseType)
                    {
                        const BindingFlags flags = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly;
                        FieldInfo field = current.GetField("m_text", flags) ?? current.GetField("m_Text", flags);
                        if (access.Text == null && field != null && field.FieldType == typeof(string)) access.Text = field;
                        field = current.GetField("m_IsTextBackingStringDirty", flags);
                        if (access.Dirty == null && field != null && field.FieldType == typeof(bool)) access.Dirty = field;
                        if (access.BufferToString == null)
                            access.BufferToString = current.GetMethod("InternalTextBackingArrayToString", flags, null, Type.EmptyTypes, null);
                    }
                    access.Fallback = type.GetProperty("text", BindingFlags.Public | BindingFlags.Instance);
                    Readers[type] = access;
                }
            }
            if (access.Dirty != null && (bool)access.Dirty.GetValue(instance) && access.BufferToString != null)
                return access.BufferToString.Invoke(instance, null) as string;
            if (access.Text != null) return access.Text.GetValue(instance) as string;
            return access.Fallback != null && access.Fallback.CanRead && access.Fallback.PropertyType == typeof(string)
                ? access.Fallback.GetValue(instance, null) as string : null;
        }
    }

    // Display fallback for MeshUI and UI paths that bypass LanguageMain/Lua table hooks.
    internal sealed class DisplayTextTranslator
    {
        // Uses the already-loaded local XUnity dictionaries. Never queues a web job.
        public Func<string, string> OfflineLookup;
        private sealed class DynamicRule
        {
            public Regex Pattern;
            public string Prefix;
            public string Japanese;
            public Dictionary<string, string> Groups;
            public int Specificity;
            public int Order;
            public bool WorldName;
            public bool ActivityRating;
        }

        private sealed class PrefixRule
        {
            public string English;
            public string Japanese;
        }

        private readonly Dictionary<string, string> exact = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> offlineExact = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> itemNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> skillNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> buffNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> mapNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> monsterNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> questTitles = new Dictionary<string, string>(StringComparer.Ordinal);
        private readonly Dictionary<string, string> chapterNames = new Dictionary<string, string>(StringComparer.Ordinal);
        private static readonly Regex MapLink = new Regex(@"\A(?<prefix>[^<>\r\n:：]+[:：])?(?<map>[^<>\r\n:：]+?)(?<coords>\([0-9]+,[0-9]+\))\z");
        private static readonly Regex FindPathLink = new Regex(@"<link=""findpath/[0-9]+(?:/[+-]?[0-9]+(?:\.[0-9]+)?){4}"">(?<label>[^<>\r\n]+)</link>");
        private static readonly Regex SpawnNotice = new Regex(@"\A(?<boss>[^<>\r\n]+?)(?: has spawned on the |が)(?<map>[^<>\r\n]+?)(?: map\.|マップに出現しました。)\z");
        private static readonly Regex RareRewardEnglish = new Regex(@"\ACongratulations to player 【[^】\r\n]+】 for defeating 【(?<boss>[^】\r\n]+)】 and earning a Rare reward!\z");
        private static readonly Regex RareRewardJapanese = new Regex(@"\Aプレイヤー【[^】\r\n]+】が【(?<boss>[^】\r\n]+)】を撃破し、レア報酬を獲得しました！\z");
        private static readonly Regex DefeatNoticeEnglish = new Regex(@"\A(?<boss>[^<>\r\n]+?) was defeated by [^<>\r\n]+\.\z");
        private static readonly Regex DefeatNoticeJapanese = new Regex(@"\A(?<boss>[^<>\r\n]+?)は[^<>\r\n]+に倒されました。\z");
        private static readonly Regex DismantleEnglish = new Regex(@"\A(?<kind>Automatically|Successfully) dismantled (?<item1>[^<>\r\n]+?) [Xx×]\s*[0-9]+ and obtained (?<item2>[^<>\r\n]+?) [Xx×]\s*[0-9]+\.\z");
        private static readonly Regex DismantleJapanese = new Regex(@"\A(?<item1>[^<>\r\n]+?) [Xx×]\s*[0-9]+を(?:自動)?解体し、(?<item2>[^<>\r\n]+?) [Xx×]\s*[0-9]+を獲得しました。\z");
        private static readonly Regex CombineSuccessEnglish = new Regex(@"\ACombine is successful\. Obtained (?<item>[^<>\r\n]+?) [Xx×]\s*[0-9]+\.\z");
        private static readonly Regex CombineSuccessJapanese = new Regex(@"\A合成成功。(?<item>[^<>\r\n]+?) [Xx×]\s*[0-9]+を獲得しました。\z");
        private static readonly Regex ObtainedCountEnglish = new Regex(@"\AObtained (?<item>[^<>\r\n]+?) (?<quantity>[Xx×]\s*[0-9]+)\z");
        private static readonly Regex ObtainedCountJapanese = new Regex(@"\A(?<item>[^<>\r\n]+?) [Xx×]\s*[0-9]+ を獲得\z");
        private static readonly Regex EquipmentType = new Regex(@"\A(?<hand>1H|2H|Off-Hand|Main-Hand)\s*-\s*(?<type>[A-Za-z ]+)\z");
        private static readonly Regex JobRequirement = new Regex(@"\A(?:Level Req\s*[:：]\s*(?<level>[0-9]+)\s*)?Job\s*Restriction\s*[:：]\s*(?<jobs>[\p{L} ,、\r\n]+)\z");
        private static readonly Regex QuestHeading = new Regex(@"\A(?<marker>\[(?:Main Quest|Side Quest|Commission|メインクエスト|サブクエスト|依頼)\])\s*(?:(?<chapter>Chapter(?: One| [0-9]+)|第[0-9]+章)[:：]\s*)?(?<title>[^<>\r\n]+)\z");
        private static readonly Regex QuestMapObjective = new Regex(@"\A(?<map>[^<>\r\n]+?)で[^\r\n]*[0-9]+/[0-9]+\s*\z");
        private static readonly Regex LifeSkillExperience = new Regex(@"\A(?<name>Gardener|Miner|Chef)\s*(?:経験(?:値)?|EXP)\s*\+[0-9]+(?:\s*\([0-9]+/[0-9]+\))?\s*\z");
        private static readonly Regex AuctionCountdown = new Regex(@"\A[0-9]{1,3}:[0-9]{2}(?::[0-9]{2})?\s*(?<suffix>Ends)\z");
        private static readonly Regex ProfileRank = new Regex(@"\A(?<label>Rank|ランク|头衔|頭銜)[:：]\s*(?<value>None|无|無)\z");
        private static readonly Regex Pickup = new Regex(@"\A(?<name>[^\r\n<>]+) (?<separator>[Xx×])\s*(?<count>[0-9]+)\z");
        private static readonly Regex Schedule = new Regex(@"\AOpens (?<day>Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\s*(?<time>[0-2][0-9]:[0-5][0-9][-～~][0-2][0-9]:[0-5][0-9])\z");
        private static readonly Regex Players = new Regex(@"\ARecommended\s+Players:\s*(?<count>[0-9]+)\z");
        private static readonly Regex Prerequisite = new Regex(@"\APrerequisite Skill (?<open><color=[^>]+>)(?<name>[^<>\r\n]+)</color>\z");
        private static readonly Regex PrerequisiteLevel = new Regex(@"(?<name>[^<>\r\n]+?)(?<level>\s*Lv\.?\s*[0-9]+)");
        private static readonly Regex SkillLevel = new Regex(@"\A(?<name>[^<>\r\n]{1,120}?)(?<level>[ \t]*Lv\.?[ \t]*[0-9]+)\z");
        private static readonly Regex MixedCountdown = new Regex(@"(?<![0-9])(?<minutes>[0-9]{1,3})\s+Minute(?:s)?\s+(?<seconds>[0-9]{1,2})\s+sec(?=後に)");
        private static readonly Regex Slot = new Regex(@"\$\{([0-9]+)\}");
        private static readonly Regex RuntimeToken = new Regex(@"\$\{[0-9]+\}|@\{[0-9]+\}|\^\{[0-9]+\}|(?<!\{)\{[0-9]+\}(?!\})");
        private static readonly Regex Markup = new Regex(@"<[^>]+>");
        private static readonly Regex Wrapper = new Regex(@"\A<(?<tag>color|size|b|i|u|s|link|mark|font|nobr|sub|sup)(?:=[^>]*)?>", RegexOptions.IgnoreCase);
        private static readonly Regex RecruitmentFooter = new Regex(@"(?<members>\[(?:Members:|メンバー:|人数：|人數：)\s*(?<count>[0-9]+)/(?<limit>[0-9]+)\])(?<gap>\r?\n[ \t]*)(?<open><color=#[0-9A-Fa-f]{6,8}><u><link=""jointeam/[0-9]+/[01]"">)(?<label>[^<>]+)(?<close></link></u></color>)\z");
        private static readonly Regex ChatSender = new Regex(@"\A<(?:#[0-9A-Fa-f]{6,8}|color=#[0-9A-Fa-f]{6,8})><nlink=openplayerInfo/[0-9]+>[^<>]*</nlink>[:：]</color>");
        private static readonly Regex ItemShareChat = new Regex(@"\A(?:[^<>:：\r\n]{1,64}[:：]\s*)?(?<phrase>(?:I )?Discover a great item! Come check it out!|すごいアイテムを見つけた！見に来て！)\s*\[(?<item>[^\[\]<>\r\n]{1,120})\]\z");
        private static readonly Regex RecruitmentBody = new Regex(@"\A(?<owner>[^<>\r\n]+?)(?:'s Party, Party Objective: |的队伍，队伍目标：|的隊伍，隊伍目標：)(?<objective>[^,，<>\r\n]+)[,，](?<message>[\s\S]*)\z");
        private static readonly HashSet<string> NumericPrefixIds = new HashSet<string>(StringComparer.Ordinal)
        {
            "10010300015",
            "10010300016",
            "10010400015",
            "10010400016",
            "10010400043",
        };
        private readonly List<DynamicRule> dynamicRules = new List<DynamicRule>();
        private readonly Dictionary<string, DynamicRule> dynamicSources = new Dictionary<string, DynamicRule>(StringComparer.Ordinal);
        private readonly Dictionary<char, List<DynamicRule>> candidateRules = new Dictionary<char, List<DynamicRule>>();
        private readonly List<DynamicRule> mapRules = new List<DynamicRule>();
        private bool rulesNeedSorting;
        private readonly List<PrefixRule> numericPrefixRules = new List<PrefixRule>();
        private Regex serverPattern;
        private string serverTranslation;
        private string questEnglish;
        private string questJapanese;
        private string serverPrefix;
        private string serverJapanesePrefix;
        private Regex questIntroduction;
        private string questIntroductionJapanese;

        public static bool IsEmptyProfileRank(string text)
        {
            if (String.IsNullOrEmpty(text) || text.Length > 200) return false;
            string value = Markup.Replace(text, "");
            return value == "无" || value == "無";
        }

        public string TranslateProfileRankValue(string text, string[] ancestry)
        {
            // In the live friend tooltip, the empty rank and its heading are
            // separate TMP components. Restrict the ambiguous single character
            // to the observed rank-value slot, never player names or chat text.
            string[] expected = { "Team_TTxt", "TeamType_TTxt", "Layout_Info", "Info", "Top_GraphicSwitchG", "TipsRoot_RTransform" };
            if (!IsEmptyProfileRank(text) || ancestry == null || ancestry.Length < expected.Length) return text;
            for (int i = 0; i < expected.Length; i++)
                if (!String.Equals(ancestry[i], expected[i], StringComparison.Ordinal)) return text;
            return ReplaceVisibleRange(text, 0, 1, LookupWord("None"));
        }

        public void AddOfflineExact(string english, string japanese)
        {
            if (String.IsNullOrEmpty(english) || japanese == null) return;
            offlineExact[english] = japanese;
            // Every canonical template is already an approved translation. The
            // old upstream ID allowlist is not a coverage boundary for display
            // text: trophies and party cards also interpolate before rendering.
            AddDynamicVariants(english, japanese, false, false, true);
        }

        // Mirrors XUnity's file escaping; shared with the regression harness.
        public static string[] DecodeDictionaryLine(string line)
        {
            if (String.IsNullOrEmpty(line)) return null;
            var result = new string[2];
            var part = new StringBuilder();
            int field = 0;
            bool escaped = false;
            for (int i = 0; i < line.Length; i++)
            {
                char c = line[i];
                if (escaped)
                {
                    if (c == 'n') part.Append('\n');
                    else if (c == 'r') part.Append('\r');
                    else if (c == '\\' || c == '=') part.Append(c);
                    else if (c == 'u' && i + 4 < line.Length)
                    {
                        ushort code;
                        if (!UInt16.TryParse(line.Substring(i + 1, 4), System.Globalization.NumberStyles.HexNumber,
                            System.Globalization.CultureInfo.InvariantCulture, out code)) return null;
                        part.Append((char)code);
                        i += 4;
                    }
                    else { part.Append('\\'); part.Append(c); }
                    escaped = false;
                }
                else if (c == '\\') escaped = true;
                else if (c == '=')
                {
                    if (field > 1) return null;
                    result[field++] = part.ToString(); part.Length = 0;
                }
                else if (c == '%' && i + 2 < line.Length && line.Substring(i, 3) == "%3D")
                {
                    part.Append('='); i += 2;
                }
                else if (c == '/' && i + 1 < line.Length && line[i + 1] == '/')
                {
                    if (field > 1) return null;
                    result[field++] = part.ToString();
                    return field == 2 ? result : null;
                }
                else part.Append(c);
            }
            if (field != 1) return null;
            result[field] = part.ToString();
            return result;
        }

        public void Add(string id, string english, string japanese)
        {
            rulesNeedSorting = true;
            english = english.Replace(@"\n", "\n");
            japanese = japanese.Replace(@"\n", "\n");
            if (id == "13150000698" || id == "13150200436")
            {
                questIntroduction = new Regex("\\A" + EscapeLiteral(english) + @"(?<gap>\r?\n)(?<rest>[\s\S]+)\z",
                    RegexOptions.Singleline, TimeSpan.FromMilliseconds(20));
                questIntroductionJapanese = japanese;
            }
            // These strings have ID-specific meanings; leave text-only lookup
            // to the canonical dictionary instead of letting the last ID win.
            if (english != "Report" && english != "Tips") exact[english] = japanese;
            if (id == "13150300004" || id == "13150300005" || id == "13150300008")
                exact[Regex.Replace(english, @"\^\{[0-9]+\}", "")] = Regex.Replace(japanese, @"\^\{[0-9]+\}", "");
            if (id.StartsWith("103600", StringComparison.Ordinal))
            {
                exact["Available for purchase at position " + english + " or above"] = japanese + "以上で購入可能";
                exact["順位" + english + "以上で購入可能"] = japanese + "以上で購入可能";
                exact[english + "以上で購入可能"] = japanese + "以上で購入可能";
            }
            if (id.StartsWith("123900", StringComparison.Ordinal)) itemNames[english] = japanese;
            if (id.StartsWith("101102", StringComparison.Ordinal) || id.StartsWith("117700", StringComparison.Ordinal))
                skillNames[english] = japanese;
            if (id.StartsWith("102202", StringComparison.Ordinal)) buffNames[english] = japanese;
            if (id.StartsWith("104700", StringComparison.Ordinal)) monsterNames[english] = japanese;
            if (id.StartsWith("131501", StringComparison.Ordinal)) questTitles[english] = japanese;
            if (id.StartsWith("131504", StringComparison.Ordinal)) chapterNames[english] = japanese;
            bool isMap = id.StartsWith("100800", StringComparison.Ordinal) || id.StartsWith("106801", StringComparison.Ordinal);
            bool isWorld = isMap || id.StartsWith("104700", StringComparison.Ordinal) || id.StartsWith("105300", StringComparison.Ordinal);
            if (isMap) mapNames[english] = japanese;
            // Every row in this curated override map used to be translated before
            // interpolation by the Recovery patch. Preserve that entire scope.
            AddDynamicVariants(english, japanese, isWorld, isMap, false);
            if (NumericPrefixIds.Contains(id) || id.StartsWith("100103", StringComparison.Ordinal) || id.StartsWith("100104", StringComparison.Ordinal) || id.StartsWith("112500", StringComparison.Ordinal))
            {
                numericPrefixRules.Add(new PrefixRule { English = english, Japanese = japanese });
            }
            if (id == "13150600321")
            {
                questEnglish = english;
                questJapanese = japanese;
            }
            // This UI substitutes values before sending the text to its renderer.
            if (id == "35031")
            {
                english = StripOuterColor(english);
                serverTranslation = StripOuterColor(japanese);
                serverPrefix = english.Split(new[] { "${1}" }, StringSplitOptions.None)[0];
                serverJapanesePrefix = serverTranslation.Split(new[] { "${1}" }, StringSplitOptions.None)[0];
                string pattern = "\\A";
                int start = 0;
                foreach (Match slot in Slot.Matches(english))
                {
                    pattern += Regex.Escape(english.Substring(start, slot.Index - start));
                    pattern += "(?<p" + slot.Groups[1].Value + ">.+?)";
                    start = slot.Index + slot.Length;
                }
                pattern += Regex.Escape(english.Substring(start)) + "\\z";
                serverPattern = new Regex(pattern, RegexOptions.Singleline, TimeSpan.FromMilliseconds(20));
            }
        }

        private void AddDynamicVariants(string source, string target, bool worldName, bool mapName, bool canonical)
        {
            if (!RuntimeToken.IsMatch(source)) return;
            DynamicRule rule = RegisterDynamicRule(source, target, worldName, canonical);
            if (rule == null) return;
            if (mapName && !mapRules.Contains(rule)) mapRules.Add(rule);
            if (source.Contains("【"))
                RegisterDynamicRule(source.Replace('【', '[').Replace('】', ']'), target.Replace('【', '[').Replace('】', ']'), worldName, canonical);
            if (source.Contains("'s "))
                RegisterDynamicRule(source.Replace("'s ", "の"), target, worldName, canonical);
        }

        private DynamicRule RegisterDynamicRule(string source, string target, bool worldName, bool canonical)
        {
            DynamicRule rule;
            if (dynamicSources.TryGetValue(source, out rule))
            {
                // Canonical/manual dictionaries override duplicate ID-derived
                // rules without compiling and scanning the same regex twice.
                if (canonical) rule.Japanese = target;
                return rule;
            }
            rule = BuildDynamicRule(source, target, worldName);
            if (rule == null) return null;
            dynamicSources[source] = rule;
            dynamicRules.Add(rule);
            rulesNeedSorting = true;
            return rule;
        }

        private static DynamicRule BuildDynamicRule(string english, string japanese, bool worldName = false)
        {
            MatchCollection tokens = RuntimeToken.Matches(english);
            if (tokens.Count == 0) return null;
            string literal = RuntimeToken.Replace(english, "").Trim();
            bool shortWorldName = literal.Length < 4 && worldName && Regex.IsMatch(literal, @"[\u3400-\u9fff]");
            bool shortCounter = literal.Length < 4 && Regex.IsMatch(english, @"\A[\u3400-\u9fff]{1,3}[@$]\{[0-9]+\}\z");
            if (literal.Length < 4 && !shortWorldName && !shortCounter) return null;

            Dictionary<string, string> groups = new Dictionary<string, string>(StringComparer.Ordinal);
            string pattern = "\\A";
            int start = 0;
            int nextGroup = 0;
            foreach (Match tokenMatch in tokens)
            {
                pattern += EscapeLiteral(english.Substring(start, tokenMatch.Index - start));
                string token = tokenMatch.Value;
                string group;
                if (groups.TryGetValue(token, out group))
                {
                    pattern += "\\k<" + group + ">";
                }
                else
                {
                    group = "d" + nextGroup++;
                    groups[token] = group;
                    if (token.StartsWith("^{", StringComparison.Ordinal))
                        pattern += "(?<" + group + ">(?:<[^>]+>)*)";
                    else
                    {
                        // An inline counter such as Test@{1} must not match a
                        // player's name beginning with Test or consume chat text.
                        bool attachedCounter = tokens.Count == 1 && !worldName
                            && Regex.IsMatch(english, @"\A[A-Za-z]+@\{[0-9]+\}\z");
                        bool levelCounter = tokens.Count == 1
                            && Regex.IsMatch(english, @"\A(?:Base|Tier|Appearance)\s+[@$]\{[0-9]+\}\z");
                        string capture = shortWorldName || shortCounter || attachedCounter || levelCounter
                            ? "(?:<[^>]+>)*[+−-]?[0-9]+(?:\\.[0-9]+)?(?:<[^>]+>)*"
                            : (english.IndexOf('\n') < 0 && english.IndexOf('\r') < 0 ? "[^\\r\\n]+?" : "[\\s\\S]+?");
                        if (english == "${1} Ends") capture = "(?:<[^>]+>)*[0-9]{1,3}:[0-9]{2}(?::[0-9]{2})?(?:<[^>]+>)*";
                        pattern += "(?<" + group + ">" + capture + ")";
                    }
                }
                start = tokenMatch.Index + tokenMatch.Length;
            }
            pattern += EscapeLiteral(english.Substring(start)) + "\\z";
            return new DynamicRule
            {
                Pattern = new Regex(pattern, RegexOptions.Singleline, TimeSpan.FromMilliseconds(20)),
                // Layouts can insert extra spaces/newlines between literal words.
                Prefix = Regex.Match(english.Substring(0, tokens[0].Index), @"\A[^\s]*").Value,
                Japanese = japanese,
                Groups = groups,
                Specificity = literal.Length,
                WorldName = worldName,
                ActivityRating = english == "Your guild's Active rating reached ${1} last week."
                    || english == "Your guildのActive rating reached ${1} last week."
                    || english == "Last Week's Active rating: ${1}"
                    || english == "Last WeekのActive rating: ${1}"
                    || english == "上周公会活跃评级达到${1}"
                    || english == "上週公會活躍評級達到${1}",
            };
        }

        private static string EscapeLiteral(string text)
        {
            return Regex.Replace(Regex.Escape(text), @"(?:\\ |\\n|\\r|\\t)+", @"\s+");
        }

        private string ApplyDynamicRule(DynamicRule rule, Match match)
        {
            return RuntimeToken.Replace(rule.Japanese, delegate(Match token)
            {
                string group;
                if (!rule.Groups.TryGetValue(token.Value, out group)) return token.Value;
                string value = match.Groups[group].Value;
                // Chinese floor labels vary only in spacing around their number.
                if (rule.WorldName && Regex.IsMatch(value, @"\A\s*[0-9]+\s*\z")) value = value.Trim();
                if (rule.ActivityRating && token.Value == "${1}") value = TranslateActivityRating(value);
                return value;
            });
        }

        private string TranslateActivityRating(string value)
        {
            string plain = Markup.Replace(value, "");
            string label = plain.Trim();
            string rank = label.EndsWith("段", StringComparison.Ordinal) ? label.Substring(0, label.Length - 1) : label;
            string english;
            switch (rank)
            {
                case "No data": case "Very Active": case "Moderately Active": case "Active": case "Very Inactive":
                    english = rank; break;
                case "比较活跃": case "比較活躍": english = "Moderately Active"; break;
                default: return value;
            }
            return ReplaceVisibleRange(value, plain.IndexOf(label, StringComparison.Ordinal), label.Length, LookupWord(english));
        }

        private static bool LooksLikeNumericSuffix(string suffix)
        {
            return Regex.IsMatch(suffix, @"\A\s*[+−-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)%?\z");
        }

        private static string StripOuterColor(string text)
        {
            string opening, closing, inner;
            if (text.StartsWith("<color=", StringComparison.Ordinal) && TryUnwrap(text, out opening, out inner, out closing))
                return inner;
            return text;
        }

        public string Translate(string text)
        {
            return Translate(text, 0);
        }

        private string Translate(string text, int depth)
        {
            if (String.IsNullOrEmpty(text)) return text;
            if (depth >= 16) return text;
            if (rulesNeedSorting)
            {
                for (int i = 0; i < dynamicRules.Count; i++) dynamicRules[i].Order = i;
                Comparison<DynamicRule> specificFirst = delegate(DynamicRule a, DynamicRule b) {
                    int comparison = b.Specificity.CompareTo(a.Specificity);
                    return comparison != 0 ? comparison : a.Order.CompareTo(b.Order);
                };
                dynamicRules.Sort(specificFirst);
                mapRules.Sort(specificFirst);
                candidateRules.Clear();
                rulesNeedSorting = false;
            }
            string translated;
            translated = TranslateWorldComposition(text);
            if (translated != text) return Translate(translated, depth + 1);
            Match lifeSkillExperience = LifeSkillExperience.Match(Markup.Replace(text, ""));
            if (lifeSkillExperience.Success)
            {
                Group name = lifeSkillExperience.Groups["name"];
                translated = LookupWord(name.Value);
                if (translated != name.Value) return ReplaceVisibleRange(text, name.Index, name.Length, translated);
            }
            // Known fixed instructions must beat templates such as Kill ${1}.
            if (offlineExact.TryGetValue(text, out translated)) return translated;
            if (exact.TryGetValue(text, out translated)) return translated;
            // Some widgets explicitly wrap static prose before assigning it.
            // Only a complete, known dictionary sentence can match this form.
            string normalized = Regex.Replace(text, @"\s+", " ").Trim();
            if (normalized != text && (offlineExact.TryGetValue(normalized, out translated)
                || exact.TryGetValue(normalized, out translated))) return translated;
            // The skill tooltip joins its localized name and level into one TMP label.
            if (text.IndexOf("Lv", StringComparison.Ordinal) >= 0)
            {
                Match skillLevel = SkillLevel.Match(text);
                if (skillLevel.Success && skillNames.TryGetValue(skillLevel.Groups["name"].Value, out translated))
                    return translated + skillLevel.Groups["level"].Value;
            }
            if (text.StartsWith("Prerequisite Skill ", StringComparison.Ordinal)
                || text.StartsWith("前提スキル ", StringComparison.Ordinal))
            {
                bool englishHeading = text.StartsWith("Prerequisite Skill ", StringComparison.Ordinal);
                string requirements = text.Substring(englishHeading ? "Prerequisite Skill ".Length : "前提スキル ".Length);
                string resolved = PrerequisiteLevel.Replace(requirements, delegate(Match match)
                {
                    string raw = match.Groups["name"].Value;
                    string name = raw.Trim();
                    int start = raw.IndexOf(name, StringComparison.Ordinal);
                    string prefix = raw.Substring(0, start);
                    string suffix = raw.Substring(start + name.Length);
                    while (name.Length > 0 && (name[0] == '+' || name[0] == '＋' || name[0] == '、'))
                    {
                        prefix += name[0];
                        name = name.Substring(1);
                        int spaces = name.Length - name.TrimStart().Length;
                        prefix += name.Substring(0, spaces);
                        name = name.Substring(spaces);
                    }
                    string known;
                    if (!skillNames.TryGetValue(name, out known) && !offlineExact.TryGetValue(name, out known)) known = name;
                    return prefix + known + suffix + match.Groups["level"].Value;
                });
                if (resolved != requirements) return "前提スキル " + resolved;
            }
            Match mixedCountdown = MixedCountdown.Match(text);
            if (mixedCountdown.Success)
                return MixedCountdown.Replace(text, "${minutes}分${seconds}秒");
            translated = TranslateRecruitment(text);
            if (translated != null) return translated;
            string opening, closing, body;
            if (TryUnwrap(text, out opening, out body, out closing))
            {
                translated = Translate(body, depth + 1);
                if (translated != body) return opening + translated + closing;
            }
            Match decoration = Regex.Match(text, @"\A(?<prefix>(?:(?:<sprite\b[^>]*>|[◆♦✦])\s*)+)(?<body>[\s\S]+)\z");
            if (decoration.Success)
            {
                body = decoration.Groups["body"].Value;
                translated = Translate(body, depth + 1);
                if (translated != body) return decoration.Groups["prefix"].Value + translated;
            }
            translated = TranslateRichComposition(text);
            if (translated != text) return translated;
            translated = TranslateQuestHeading(text, depth);
            if (translated != null) return translated;
            Match rank = ProfileRank.Match(Markup.Replace(text, ""));
            if (rank.Success)
            {
                Group value = rank.Groups["value"], label = rank.Groups["label"];
                translated = ReplaceVisibleRange(text, value.Index, value.Length, LookupWord("None"));
                return ReplaceVisibleRange(translated, label.Index, label.Length, LookupWord("Rank"));
            }
            Match countdown = AuctionCountdown.Match(Markup.Replace(text, ""));
            if (countdown.Success && offlineExact.TryGetValue("${1} Ends", out translated)
                && translated.StartsWith("${1}", StringComparison.Ordinal))
                return ReplaceVisibleRange(text, countdown.Groups["suffix"].Index, 4, translated.Substring(4).TrimStart());
            // The quest panel appends the independently formatted server-cap
            // block to its static introduction in one TMP component. Translate
            // both blocks before returning, including already-localized tails.
            if (questIntroduction != null)
            {
                Match introduction = questIntroduction.Match(text);
                if (introduction.Success)
                    return questIntroductionJapanese + introduction.Groups["gap"].Value
                        + Translate(introduction.Groups["rest"].Value, depth + 1);
            }
            // Resonance composes a known effect with a separately colored current value.
            Match current = Regex.Match(text, @"\A(?<description>For every [\s\S]+?\.)\s*\[Current\s+(?<value>(?:<[^>]+>)*[+−-]?[0-9]+(?:\.[0-9]+)?(?:<[^>]+>)*)\]\z");
            if (current.Success)
            {
                body = current.Groups["description"].Value;
                translated = Translate(body, depth + 1);
                if (translated != body) return translated + "【現在 " + current.Groups["value"].Value + "】";
            }
            int colon = text.IndexOfAny(new[] { ':', '：' });
            string skill;
            if (colon > 0 && skillNames.TryGetValue(text.Substring(0, colon).Trim(), out skill))
            {
                body = text.Substring(colon + 1).TrimStart();
                translated = Translate(body, depth + 1);
                if (translated != body) return skill + "：" + translated;
            }
            Match schedule = Schedule.Match(text);
            if (schedule.Success)
            {
                string[] days = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
                string[] japaneseDays = { "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日", "日曜日" };
                return japaneseDays[Array.IndexOf(days, schedule.Groups["day"].Value)] + " " + schedule.Groups["time"].Value + " 開催";
            }
            Match players = Players.Match(text);
            if (players.Success) return "推奨人数：" + players.Groups["count"].Value;
            Match layout = JobRequirement.Match(text);
            if (layout.Success)
            {
                string[] names = layout.Groups["jobs"].Value.Split(new[] { ',', '、' });
                for (int i = 0; i < names.Length; i++)
                {
                    string name = Regex.Replace(names[i].Trim(), @"\s+", " ");
                    string originalName = name;
                    name = Regex.Replace(name, @"(?<=[a-z])(?=[A-Z])", " ");
                    names[i] = LookupWord(name);
                    if (names[i] == name) names[i] = originalName;
                }
                return (layout.Groups["level"].Success ? "必要レベル: " + layout.Groups["level"].Value + "\n" : "")
                    + "ジョブ制限：" + String.Join("、", names);
            }
            layout = EquipmentType.Match(text);
            if (layout.Success) return LookupWord(layout.Groups["hand"].Value) + " - " + LookupWord(layout.Groups["type"].Value.Trim());
            layout = MapLink.Match(text);
            if (layout.Success)
            {
                string name = layout.Groups["map"].Value;
                translated = TranslateMapName(name);
                return layout.Groups["prefix"].Value + translated + layout.Groups["coords"].Value;
            }
            Match composed = Pickup.Match(text);
            if (composed.Success && TryCountedName(composed.Groups["name"].Value, out translated))
                return translated + " " + composed.Groups["separator"].Value + (composed.Groups["separator"].Value == "X" ? " " : "") + composed.Groups["count"].Value;
            composed = Prerequisite.Match(text);
            if (composed.Success)
            {
                string name = composed.Groups["name"].Value;
                if (!skillNames.TryGetValue(name, out translated) && !offlineExact.TryGetValue(name, out translated)) translated = name;
                return "前提スキル " + composed.Groups["open"].Value + translated + "</color>";
            }
            int end = text.Length;
            while (end > 0 && text[end - 1] == '!') end--;
            if (end != text.Length && exact.TryGetValue(text.Substring(0, end), out translated))
                return translated + text.Substring(end);
            List<DynamicRule> candidates;
            if (!candidateRules.TryGetValue(text[0], out candidates))
            {
                candidates = new List<DynamicRule>();
                foreach (DynamicRule candidate in dynamicRules)
                    if (candidate.Prefix.Length == 0 || candidate.Prefix[0] == text[0]) candidates.Add(candidate);
                if (candidateRules.Count < 256) candidateRules[text[0]] = candidates;
            }
            foreach (DynamicRule rule in candidates)
            {
                if (!text.StartsWith(rule.Prefix, StringComparison.Ordinal)) continue;
                try
                {
                    Match match = rule.Pattern.Match(text);
                    if (match.Success) return ApplyDynamicRule(rule, match);
                }
                catch (RegexMatchTimeoutException) { /* Leave unexpected text unchanged. */ }
            }
            foreach (PrefixRule rule in numericPrefixRules)
            {
                if (!text.StartsWith(rule.English, StringComparison.Ordinal)) continue;
                string suffix = text.Substring(rule.English.Length);
                if (LooksLikeNumericSuffix(suffix)) return rule.Japanese + suffix;
            }
            if (serverPattern != null && text.StartsWith("Current Server Level Cap:", StringComparison.Ordinal))
            {
                try
                {
                    Match match = serverPattern.Match(text);
                    if (match.Success)
                        return Slot.Replace(serverTranslation, delegate(Match slot) { return match.Groups["p" + slot.Groups[1].Value].Value; });
                }
                catch (RegexMatchTimeoutException) { /* Leave unexpected text unchanged. */ }
            }
            // Specific known templates must win over broad dictionary regexes
            // (possessives and server notices can otherwise swallow whole lines).
            string original = text;
            // Quest tracker renders a combined rich-text block; XUnity can already
            // have translated its other lines. Replace only these known literals.
            if (!String.IsNullOrEmpty(questEnglish)) text = text.Replace(questEnglish, questJapanese);
            if (!String.IsNullOrEmpty(serverPrefix)) text = text.Replace(serverPrefix, serverJapanesePrefix);
            if (text != original) return text;
            string trimmed = text.Trim();
            if (trimmed != text && trimmed.Length > 0)
            {
                translated = Translate(trimmed, depth + 1);
                if (translated != trimmed)
                {
                    int start = text.IndexOf(trimmed, StringComparison.Ordinal);
                    return text.Substring(0, start) + translated + text.Substring(start + trimmed.Length);
                }
            }
            if (OfflineLookup != null)
            {
                translated = OfflineLookup(text);
                if (!String.IsNullOrEmpty(translated)) return translated;
            }
            return text;
        }

        private string TranslateRichComposition(string text)
        {
            if (text.IndexOf('<') < 0) return text;
            string plain = Markup.Replace(text, "");
            Match match = Pickup.Match(plain);
            string translated;
            if (match.Success && TryCountedName(match.Groups["name"].Value, out translated))
                return ReplaceVisibleRange(text, match.Groups["name"].Index, match.Groups["name"].Length, translated);
            match = MapLink.Match(plain);
            if (match.Success)
            {
                string name = match.Groups["map"].Value;
                translated = TranslateMapName(name);
                if (translated != name)
                    return ReplaceVisibleRange(text, match.Groups["map"].Index, name.Length, translated);
            }
            return text;
        }

        private bool TryCountedName(string name, out string translated)
        {
            // The skill link tooltip appends a stack count to a buff name just
            // like item pickup labels. Only registered item/buff names qualify.
            return itemNames.TryGetValue(name, out translated) || buffNames.TryGetValue(name, out translated);
        }

        private string TranslateWorldComposition(string text)
        {
            // Item-share chat inserts a linked item name after the localized
            // template. Preserve the sender and link markup; only the fixed
            // sentence and a name present in the item ID table may change.
            if (text.IndexOf("Discover a great item! Come check it out!", StringComparison.Ordinal) >= 0
                || text.IndexOf("すごいアイテムを見つけた！見に来て！", StringComparison.Ordinal) >= 0)
            {
                Match share = ItemShareChat.Match(Markup.Replace(text, ""));
                if (share.Success)
                {
                    string item, phrase = LookupWord("I Discover a great item! Come check it out!");
                    if (itemNames.TryGetValue(share.Groups["item"].Value, out item)
                        && phrase != "I Discover a great item! Come check it out!")
                    {
                        Group name = share.Groups["item"], sentence = share.Groups["phrase"];
                        string sharedText = ReplaceVisibleRange(text, name.Index, name.Length, item);
                        return ReplaceVisibleRange(sharedText, sentence.Index, sentence.Length, phrase);
                    }
                }
            }
            // A findpath link is a typed system field even inside a player's
            // custom message or a system notice. Modify its known map label
            // only; leave the sender, route, coordinates and surrounding prose.
            string result = text.IndexOf("findpath/", StringComparison.Ordinal) < 0 ? text
                : FindPathLink.Replace(text, delegate(Match link)
                {
                    Group label = link.Groups["label"];
                    Match map = MapLink.Match(label.Value);
                    if (!map.Success || map.Groups["prefix"].Success) return link.Value;
                    string name = map.Groups["map"].Value;
                    string replacement = TranslateMapName(name);
                    if (replacement == name) return link.Value;
                    int offset = label.Index - link.Index + map.Groups["map"].Index;
                    return link.Value.Substring(0, offset) + replacement + link.Value.Substring(offset + name.Length);
                });
            Match objective = QuestMapObjective.Match(Markup.Replace(result, ""));
            if (objective.Success)
            {
                Group map = objective.Groups["map"];
                string objectiveMapTranslation = TranslateMapName(map.Value);
                if (objectiveMapTranslation != map.Value)
                    result = ReplaceVisibleRange(result, map.Index, map.Length, objectiveMapTranslation);
            }
            bool dismantleCandidate = result.IndexOf(" dismantled ", StringComparison.Ordinal) >= 0
                || result.IndexOf("解体し、", StringComparison.Ordinal) >= 0;
            bool combineCandidate = result.IndexOf("Combine is successful. Obtained ", StringComparison.Ordinal) >= 0
                || result.IndexOf("合成成功。", StringComparison.Ordinal) >= 0;
            bool obtainedCandidate = result.IndexOf("Obtained ", StringComparison.Ordinal) >= 0
                || result.IndexOf(" を獲得", StringComparison.Ordinal) >= 0;
            bool rewardCandidate = result.IndexOf("Congratulations to player", StringComparison.Ordinal) >= 0
                || result.IndexOf("レア報酬を獲得", StringComparison.Ordinal) >= 0;
            bool defeatCandidate = result.IndexOf(" was defeated by ", StringComparison.Ordinal) >= 0
                || result.IndexOf("に倒されました。", StringComparison.Ordinal) >= 0;
            bool spawnCandidate = result.IndexOf(" has spawned on the ", StringComparison.Ordinal) >= 0
                || result.IndexOf("マップに出現しました。", StringComparison.Ordinal) >= 0;
            if (!dismantleCandidate && !combineCandidate && !obtainedCandidate && !rewardCandidate && !defeatCandidate && !spawnCandidate) return result;
            string visible = Markup.Replace(result, "");
            if (dismantleCandidate)
            {
                Match dismantle = DismantleEnglish.Match(visible);
                bool english = dismantle.Success;
                if (!english) dismantle = DismantleJapanese.Match(visible);
                if (dismantle.Success)
                {
                    Group first = dismantle.Groups["item1"], second = dismantle.Groups["item2"];
                    string firstJapanese, secondJapanese;
                    // Work right to left so visible positions still refer to the source.
                    if (english) result = ReplaceVisibleRange(result, visible.Length - 1, 1, "を獲得しました。");
                    if (itemNames.TryGetValue(second.Value, out secondJapanese) && secondJapanese != second.Value)
                        result = ReplaceVisibleRange(result, second.Index, second.Length, secondJapanese);
                    if (english)
                        result = ReplaceVisibleRange(result, visible.IndexOf(" and obtained ", StringComparison.Ordinal), " and obtained ".Length,
                            dismantle.Groups["kind"].Value == "Automatically" ? "を自動解体し、" : "を解体し、");
                    if (itemNames.TryGetValue(first.Value, out firstJapanese) && firstJapanese != first.Value)
                        result = ReplaceVisibleRange(result, first.Index, first.Length, firstJapanese);
                    if (english) result = ReplaceVisibleRange(result, 0, dismantle.Groups["kind"].Length + " dismantled ".Length, "");
                    if (result != text) return result;
                }
            }
            if (combineCandidate)
            {
                Match combine = CombineSuccessEnglish.Match(visible);
                bool english = combine.Success;
                if (!english) combine = CombineSuccessJapanese.Match(visible);
                if (combine.Success)
                {
                    Group item = combine.Groups["item"];
                    string localized;
                    if (english) result = ReplaceVisibleRange(result, visible.Length - 1, 1, "を獲得しました。");
                    if (itemNames.TryGetValue(item.Value, out localized) && localized != item.Value)
                        result = ReplaceVisibleRange(result, item.Index, item.Length, localized);
                    if (english) result = ReplaceVisibleRange(result, 0, "Combine is successful. Obtained ".Length, "合成成功。");
                    if (result != text) return result;
                }
            }
            if (obtainedCandidate)
            {
                Match obtained = ObtainedCountEnglish.Match(visible);
                bool english = obtained.Success;
                if (!english) obtained = ObtainedCountJapanese.Match(visible);
                if (obtained.Success)
                {
                    Group item = obtained.Groups["item"];
                    string localized;
                    if (english)
                    {
                        Group quantity = obtained.Groups["quantity"];
                        result = ReplaceVisibleRange(result, quantity.Index, quantity.Length, quantity.Value + " を獲得");
                    }
                    if (itemNames.TryGetValue(item.Value, out localized) && localized != item.Value)
                        result = ReplaceVisibleRange(result, item.Index, item.Length, localized);
                    if (english) result = ReplaceVisibleRange(result, 0, "Obtained ".Length, "");
                    if (result != text) return result;
                }
            }
            // The system announcement interpolates a live monster name after
            // localizing its sentence. Match the complete notice and change
            // only its typed monster slot; player names and chat stay intact.
            if (rewardCandidate)
            {
                Match reward = RareRewardEnglish.Match(visible);
                if (!reward.Success) reward = RareRewardJapanese.Match(visible);
                if (reward.Success)
                {
                    Group monster = reward.Groups["boss"];
                    string localized;
                    if (monsterNames.TryGetValue(monster.Value, out localized) && localized != monster.Value)
                        return ReplaceVisibleRange(result, monster.Index, monster.Length, localized);
                }
            }
            if (defeatCandidate)
            {
                Match defeat = DefeatNoticeEnglish.Match(visible);
                if (!defeat.Success) defeat = DefeatNoticeJapanese.Match(visible);
                if (defeat.Success)
                {
                    Group monster = defeat.Groups["boss"];
                    string localized;
                    if (monsterNames.TryGetValue(monster.Value, out localized) && localized != monster.Value)
                        return ReplaceVisibleRange(result, monster.Index, monster.Length, localized);
                }
            }
            if (!spawnCandidate) return result;
            Match notice = SpawnNotice.Match(visible);
            if (!notice.Success) return result;
            string boss = notice.Groups["boss"].Value, translatedBoss;
            if (!monsterNames.TryGetValue(boss, out translatedBoss))
            {
                if (!monsterNames.ContainsValue(boss)) return result;
                translatedBoss = boss;
            }
            Group region = notice.Groups["map"];
            string translatedMap = TranslateMapName(region.Value);
            if (translatedMap == region.Value && !mapNames.ContainsValue(region.Value)) return result;
            result = ReplaceVisibleRange(result, region.Index, region.Length, translatedMap);
            return ReplaceVisibleRange(result, notice.Groups["boss"].Index, boss.Length, translatedBoss);
        }

        private string TranslateQuestHeading(string text, int depth)
        {
            if (!text.StartsWith("[", StringComparison.Ordinal) && !text.StartsWith("<", StringComparison.Ordinal)) return null;
            Match heading = QuestHeading.Match(Markup.Replace(text, ""));
            if (!heading.Success) return null;
            string title = heading.Groups["title"].Value;
            string translatedTitle;
            if (!questTitles.TryGetValue(title, out translatedTitle))
            {
                if (questTitles.ContainsValue(title)) translatedTitle = title;
                else
                {
                    translatedTitle = Translate(title, depth + 1);
                    if (translatedTitle == title) return text;
                }
            }
            // Work backwards through visible spans so TMP color/link boundaries
            // and the original chapter punctuation remain byte-for-byte intact.
            string result = ReplaceVisibleRange(text, heading.Groups["title"].Index, title.Length, translatedTitle);
            Group chapter = heading.Groups["chapter"];
            string translatedChapter;
            if (chapter.Success && chapterNames.TryGetValue(chapter.Value, out translatedChapter))
                result = ReplaceVisibleRange(result, chapter.Index, chapter.Length, translatedChapter);
            Group marker = heading.Groups["marker"];
            return ReplaceVisibleRange(result, marker.Index, marker.Length, LookupWord(marker.Value));
        }

        private string TranslateRecruitment(string text)
        {
            if (text.IndexOf("jointeam/", StringComparison.Ordinal) < 0) return null;
            Match footer = RecruitmentFooter.Match(text);
            if (!footer.Success) return null;
            string join = LookupWord("Tap to Join Party");
            if (join == "Tap to Join Party") return null;
            string label = footer.Groups["label"].Value;
            if (label != "Tap to Join Party" && label != "点击组队" && label != "點擊組隊" && label != join) return null;

            Match sender = ChatSender.Match(text);
            string prefix = sender.Success ? sender.Value : "";
            string body = text.Substring(prefix.Length, footer.Index - prefix.Length);
            if (body.IndexOf('<') >= 0) return null;
            string members = "[Members: " + footer.Groups["count"].Value + "/" + footer.Groups["limit"].Value + "]";
            string translatedMembers = FormatKnownTemplate("${1}[Members: ${2}/${3}]\n${4}", "", footer.Groups["count"].Value, footer.Groups["limit"].Value, "").TrimEnd('\r', '\n');

            // Reuse the existing whole-card rules for dungeon shorthand and
            // known objectives after separating the immutable link wrappers.
            if (OfflineLookup != null && RecruitmentBody.IsMatch(body))
            {
                string normalized = body + members + "\nTap to Join Party";
                string candidate = OfflineLookup(normalized);
                string suffix = translatedMembers + "\n" + join;
                if (!String.IsNullOrEmpty(candidate) && candidate.EndsWith(suffix, StringComparison.Ordinal))
                    body = candidate.Substring(0, candidate.Length - suffix.Length);
            }

            // Other objectives (including monster names) use the same fixed
            // party templates. Only the system fields and default welcome are
            // localized; the player's custom recruitment sentence stays intact.
            Match structured = RecruitmentBody.Match(body);
            if (structured.Success)
            {
                string party = FormatKnownTemplate("${1}'s Party", structured.Groups["owner"].Value);
                string objective = LookupWord(structured.Groups["objective"].Value);
                string message = structured.Groups["message"].Value;
                if (message == "We look forward to welcoming all Adventurers!" || message == "期待各位冒险者的加入！" || message == "期待各位冒險者的加入！")
                    message = LookupWord("We look forward to welcoming all Adventurers!");
                body = FormatKnownTemplate("${1}, Party Objective: ${2},", party, objective) + message;
            }
            return prefix + body + translatedMembers + footer.Groups["gap"].Value
                + footer.Groups["open"].Value + join + footer.Groups["close"].Value;
        }

        private string FormatKnownTemplate(string source, params string[] values)
        {
            return Slot.Replace(LookupWord(source), delegate(Match slot)
            {
                int index = Int32.Parse(slot.Groups[1].Value) - 1;
                return index >= 0 && index < values.Length ? values[index] : slot.Value;
            });
        }

        private string TranslateMapName(string name)
        {
            string translated;
            if (mapNames.TryGetValue(name, out translated)) return translated;
            foreach (DynamicRule rule in mapRules)
            {
                try
                {
                    Match match = rule.Pattern.Match(name);
                    if (match.Success) return ApplyDynamicRule(rule, match);
                }
                catch (RegexMatchTimeoutException) { }
            }
            return name;
        }

        private static string ReplaceVisibleRange(string text, int start, int length, string replacement)
        {
            int visible = 0, rawStart = -1, rawEnd = -1;
            for (int i = 0; i < text.Length; i++)
            {
                if (text[i] == '<')
                {
                    int end = text.IndexOf('>', i);
                    if (end < 0) return text;
                    i = end;
                    continue;
                }
                if (visible == start) rawStart = i;
                if (++visible == start + length) { rawEnd = i + 1; break; }
            }
            if (rawStart < 0 || rawEnd < 0) return text;
            string original = text.Substring(rawStart, rawEnd - rawStart);
            // Keep link boundaries and internally styled names intact.
            if (original.IndexOf('<') >= 0) return text;
            return text.Substring(0, rawStart) + replacement + text.Substring(rawEnd);
        }

        private static bool TryUnwrap(string text, out string opening, out string inner, out string closing)
        {
            opening = inner = closing = null;
            Match first = Wrapper.Match(text);
            if (!first.Success) return false;
            string tag = first.Groups["tag"].Value;
            int depth = 0;
            foreach (Match match in Regex.Matches(text, @"</?" + tag + @"(?:=[^>]*)?>", RegexOptions.IgnoreCase))
            {
                depth += match.Value.StartsWith("</", StringComparison.Ordinal) ? -1 : 1;
                if (depth != 0) continue;
                if (match.Index + match.Length != text.Length) return false;
                opening = first.Value;
                inner = text.Substring(first.Length, match.Index - first.Length);
                closing = match.Value;
                return true;
            }
            return false;
        }

        private string LookupWord(string word)
        {
            string translated;
            if (offlineExact.TryGetValue(word, out translated)) return translated;
            if (exact.TryGetValue(word, out translated)) return translated;
            translated = OfflineLookup == null ? null : OfflineLookup(word);
            return String.IsNullOrEmpty(translated) ? word : translated;
        }
    }

    // Only message widgets, never the channel tabs, input field, or scroll list.
    internal static class ChatDisplayGate
    {
        private static readonly string[] MessageWidgets = {
            "UI_Sys_Main_ChatWidget", "UI_Sys_Chat_MineNewWidget",
            "UI_Sys_Chat_OtherNewWidget", "UI_Sys_Friend_ChatListLeftWidget",
            "UI_Sys_Friend_ChatListRightWidget"
        };
        public static bool IsChatMessagePath(IList<string> ancestorNames)
        {
            foreach (string name in ancestorNames)
            {
                if (name == null) continue;
                foreach (string prefix in MessageWidgets)
                    if (name.StartsWith(prefix, StringComparison.Ordinal)) return true;
            }
            return false;
        }
    }
}

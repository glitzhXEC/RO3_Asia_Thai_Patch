using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace RO3.JapaneseMod
{
    // Upstream localization fix used by Issues #1/#2/#3.
    //
    // The prerequisite popup resolves skill IDs through Lua_CFG_SkillConfig.GetName,
    // which calls Language.Trans(_iName).  By the time the normal runtime table
    // patcher observes Localization_en, parts of SkillConfig have already cached
    // those strings.  Patch the Recovery localization payload on disk during
    // BepInEx Awake instead, before RO3 loads either localization module.
    internal static class RecoveryLocalizationPatcher
    {
        private const string MonsterNameIdPrefix = "105300";
        private const string BackupSuffix = ".ro3-ja-original";
        private const int MinimumExpectedCanonicalEntries = 8000;
        private const int MinimumExpectedDirectEntries = 6000;
        private const int MinimumExpectedMonsterNames = 150;
        private const int PartialPatchDetectionThreshold = 100;
        private static readonly string[] KnownMonsterNameProbes =
        {
            "Familiar",
            "Piere",
            "Isis",
            "Smokie",
            "Magnolia",
        };
        private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);
        private static readonly string[] TargetModules =
        {
            "Localization_en",
            "Localization_zh_CN",
            "Localization_zh_TW",
        };

        private sealed class LocalizationEntry
        {
            public string English;
            public string Japanese;
        }

        private sealed class LuaStringLocation
        {
            public int LengthStart;
            public int PayloadEnd;
            public byte[] Cipher;
        }

        private sealed class LuaConstant
        {
            public int Tag;
            public long Integer;
            public bool HasInteger;
            public LuaStringLocation String;
        }

        private sealed class Replacement
        {
            public int Start;
            public int End;
            public byte[] Bytes;
        }

        private sealed class Candidate
        {
            public long Id;
            public LuaStringLocation Location;
            public string Decoded;
        }

        private sealed class ModulePatch
        {
            public string LogicalModule;
            public string PayloadPath;
            public byte[] Original;
            public byte[] Patched;
            public int ReplaceCount;
            public int AlreadyJapaneseCount;
            public int CandidateCount;
            public int MonsterNameCandidateCount;
        }

        private sealed class LuaReader
        {
            private readonly byte[] _data;
            private int _position;

            public LuaReader(byte[] data)
            {
                _data = data;
            }

            public int Position
            {
                get { return _position; }
            }

            public int Length
            {
                get { return _data.Length; }
            }

            public byte ReadByte()
            {
                if (_position >= _data.Length)
                {
                    throw new InvalidDataException("Unexpected end of Lua chunk.");
                }
                return _data[_position++];
            }

            public byte[] ReadBytes(int count)
            {
                if (count < 0 || _position + count > _data.Length)
                {
                    throw new InvalidDataException("Unexpected end of Lua chunk.");
                }
                byte[] value = new byte[count];
                Buffer.BlockCopy(_data, _position, value, 0, count);
                _position += count;
                return value;
            }

            public void Skip(int count)
            {
                if (count < 0 || _position + count > _data.Length)
                {
                    throw new InvalidDataException("Unexpected end of Lua chunk.");
                }
                _position += count;
            }

            public long ReadInt64()
            {
                byte[] bytes = ReadBytes(8);
                return BitConverter.ToInt64(bytes, 0);
            }

            public double ReadDouble()
            {
                byte[] bytes = ReadBytes(8);
                return BitConverter.ToDouble(bytes, 0);
            }

            public int ReadVarint()
            {
                long value = 0;
                while (true)
                {
                    byte current = ReadByte();
                    value = checked(value * 128L + (current & 0x7f));
                    if ((current & 0x80) != 0)
                    {
                        if (value > Int32.MaxValue)
                        {
                            throw new InvalidDataException("Lua varint is too large.");
                        }
                        return (int)value;
                    }
                }
            }

            public LuaStringLocation ReadLuaString()
            {
                int lengthStart = _position;
                int encodedLength = ReadVarint();
                if (encodedLength == 0)
                {
                    return null;
                }
                int byteLength = encodedLength - 1;
                byte[] payload = ReadBytes(byteLength);
                return new LuaStringLocation
                {
                    LengthStart = lengthStart,
                    PayloadEnd = _position,
                    Cipher = payload,
                };
            }
        }

        private sealed class JsonParser
        {
            private readonly string _text;
            private int _position;

            public JsonParser(string text)
            {
                _text = text;
            }

            public object Parse()
            {
                SkipWhitespace();
                object value = ParseValue();
                SkipWhitespace();
                if (_position != _text.Length)
                {
                    throw new InvalidDataException("Unexpected trailing JSON data.");
                }
                return value;
            }

            private object ParseValue()
            {
                SkipWhitespace();
                if (_position >= _text.Length)
                {
                    throw new InvalidDataException("Unexpected end of JSON.");
                }
                char current = _text[_position];
                if (current == '{') return ParseObject();
                if (current == '[') return ParseArray();
                if (current == '"') return ParseString();
                if (current == 't') { Expect("true"); return true; }
                if (current == 'f') { Expect("false"); return false; }
                if (current == 'n') { Expect("null"); return null; }
                return ParseNumber();
            }

            private Dictionary<string, object> ParseObject()
            {
                Dictionary<string, object> result =
                    new Dictionary<string, object>(StringComparer.Ordinal);
                _position++;
                SkipWhitespace();
                if (TryConsume('}')) return result;
                while (true)
                {
                    SkipWhitespace();
                    string key = ParseString();
                    SkipWhitespace();
                    Require(':');
                    result[key] = ParseValue();
                    SkipWhitespace();
                    if (TryConsume('}')) return result;
                    Require(',');
                }
            }

            private List<object> ParseArray()
            {
                List<object> result = new List<object>();
                _position++;
                SkipWhitespace();
                if (TryConsume(']')) return result;
                while (true)
                {
                    result.Add(ParseValue());
                    SkipWhitespace();
                    if (TryConsume(']')) return result;
                    Require(',');
                }
            }

            private string ParseString()
            {
                Require('"');
                StringBuilder value = new StringBuilder();
                while (_position < _text.Length)
                {
                    char current = _text[_position++];
                    if (current == '"') return value.ToString();
                    if (current != '\\')
                    {
                        value.Append(current);
                        continue;
                    }
                    if (_position >= _text.Length)
                    {
                        throw new InvalidDataException("Invalid JSON escape.");
                    }
                    char escaped = _text[_position++];
                    switch (escaped)
                    {
                        case '"': value.Append('"'); break;
                        case '\\': value.Append('\\'); break;
                        case '/': value.Append('/'); break;
                        case 'b': value.Append('\b'); break;
                        case 'f': value.Append('\f'); break;
                        case 'n': value.Append('\n'); break;
                        case 'r': value.Append('\r'); break;
                        case 't': value.Append('\t'); break;
                        case 'u':
                            if (_position + 4 > _text.Length)
                            {
                                throw new InvalidDataException("Invalid JSON unicode escape.");
                            }
                            value.Append((char)Int32.Parse(
                                _text.Substring(_position, 4),
                                NumberStyles.HexNumber,
                                CultureInfo.InvariantCulture));
                            _position += 4;
                            break;
                        default:
                            throw new InvalidDataException("Invalid JSON escape character.");
                    }
                }
                throw new InvalidDataException("Unterminated JSON string.");
            }

            private object ParseNumber()
            {
                int start = _position;
                if (_text[_position] == '-') _position++;
                while (_position < _text.Length && Char.IsDigit(_text[_position])) _position++;
                bool floating = false;
                if (_position < _text.Length && _text[_position] == '.')
                {
                    floating = true;
                    _position++;
                    while (_position < _text.Length && Char.IsDigit(_text[_position])) _position++;
                }
                if (_position < _text.Length &&
                    (_text[_position] == 'e' || _text[_position] == 'E'))
                {
                    floating = true;
                    _position++;
                    if (_position < _text.Length &&
                        (_text[_position] == '+' || _text[_position] == '-')) _position++;
                    while (_position < _text.Length && Char.IsDigit(_text[_position])) _position++;
                }
                string token = _text.Substring(start, _position - start);
                if (floating)
                {
                    double doubleValue;
                    if (!Double.TryParse(token, NumberStyles.Float,
                            CultureInfo.InvariantCulture, out doubleValue))
                    {
                        throw new InvalidDataException("Invalid JSON number.");
                    }
                    return doubleValue;
                }
                long longValue;
                if (!Int64.TryParse(token, NumberStyles.Integer,
                        CultureInfo.InvariantCulture, out longValue))
                {
                    throw new InvalidDataException("Invalid JSON integer.");
                }
                return longValue;
            }

            private void Expect(string token)
            {
                if (_position + token.Length > _text.Length ||
                    String.CompareOrdinal(_text, _position, token, 0, token.Length) != 0)
                {
                    throw new InvalidDataException("Invalid JSON token.");
                }
                _position += token.Length;
            }

            private void Require(char expected)
            {
                SkipWhitespace();
                if (_position >= _text.Length || _text[_position] != expected)
                {
                    throw new InvalidDataException("Expected JSON character: " + expected);
                }
                _position++;
            }

            private bool TryConsume(char value)
            {
                if (_position < _text.Length && _text[_position] == value)
                {
                    _position++;
                    return true;
                }
                return false;
            }

            private void SkipWhitespace()
            {
                while (_position < _text.Length && Char.IsWhiteSpace(_text[_position]))
                {
                    _position++;
                }
            }
        }

        public static string Apply(string gameRoot, string mappingPath)
        {
            if (String.IsNullOrEmpty(gameRoot))
            {
                throw new ArgumentException("Game root is empty.", "gameRoot");
            }
            if (!File.Exists(mappingPath))
            {
                throw new FileNotFoundException("Localization mapping was not found.", mappingPath);
            }

            string recoveryRoot = Path.Combine(
                gameRoot, "ro3_Data", "StreamingAssets", "Recovery");
            string manifestPath = Path.Combine(
                recoveryRoot, "recovery-compatibility-manifest.json");
            if (!File.Exists(manifestPath))
            {
                return "Recovery manifest is absent; no upstream patch was applied.";
            }
            return ApplyInternal(recoveryRoot, manifestPath, mappingPath, true);
        }

        private static string ApplyInternal(
            string recoveryRoot,
            string manifestPath,
            string mappingPath,
            bool allowBackupRecovery)
        {
            Dictionary<long, LocalizationEntry> mapping = LoadCanonicalMap(mappingPath);
            Dictionary<string, object> manifest = ParseManifest(manifestPath);
            ValidateManifestIdentity(manifest);

            List<ModulePatch> modules = new List<ModulePatch>();
            bool payloadMismatch = false;
            for (int index = 0; index < TargetModules.Length; index++)
            {
                string logicalModule = TargetModules[index];
                Dictionary<string, object> record = FindModule(manifest, logicalModule);
                string relativePath = GetString(record, "payload_relative_path");
                string payloadPath = Path.Combine(recoveryRoot, "LuaPayload", relativePath);
                byte[] original = File.ReadAllBytes(payloadPath);
                long expectedSize = GetInt64(record, "payload_size");
                string expectedHash = GetString(record, "payload_sha256");
                if (original.LongLength != expectedSize ||
                    !String.Equals(Sha256(original), expectedHash,
                        StringComparison.OrdinalIgnoreCase))
                {
                    payloadMismatch = true;
                    break;
                }

                ModulePatch prepared;
                try
                {
                    prepared = PrepareModule(
                        logicalModule,
                        payloadPath,
                        original,
                        mapping,
                        String.Equals(logicalModule, "Localization_en", StringComparison.Ordinal));
                }
                catch (InvalidDataException)
                {
                    // The currently installed Recovery payload may already contain
                    // Japanese values from an older canonical map. A later rename
                    // (for example a corrected monster name) can then make the
                    // fallback scanner see neither the original English string nor
                    // the new Japanese string and fail before the normal partial-
                    // patch recovery path is reached. Restore the verified pristine
                    // same-build backup once and rebuild from the latest map.
                    if (allowBackupRecovery &&
                        TryRestoreSameBuildBackups(recoveryRoot, manifestPath, manifest))
                    {
                        return ApplyInternal(recoveryRoot, manifestPath, mappingPath, false);
                    }
                    throw;
                }
                modules.Add(prepared);
            }

            if (payloadMismatch)
            {
                if (allowBackupRecovery && TryRestoreSameBuildBackups(recoveryRoot, manifestPath, manifest))
                {
                    return ApplyInternal(recoveryRoot, manifestPath, mappingPath, false);
                }
                throw new InvalidDataException(
                    "Recovery payload hash/size does not match its manifest.");
            }

            int totalReplace = 0;
            int totalJapanese = 0;
            for (int index = 0; index < modules.Count; index++)
            {
                totalReplace += modules[index].ReplaceCount;
                totalJapanese += modules[index].AlreadyJapaneseCount;
            }
            if (totalReplace == 0)
            {
                if (totalJapanese < MinimumExpectedDirectEntries * TargetModules.Length)
                {
                    throw new InvalidDataException(
                        "Recovery localization table was unexpectedly small after inspection.");
                }
                WritePatchState(manifestPath, mappingPath);
                return FormatStatus("already patched", modules);
            }

            // A mixed English/Japanese state can also be the normal result of
            // expanding the canonical mapping after a previous successful patch.
            // PrepareModule only treats values matching the expected source or
            // Japanese value as direct English candidates, so finishing the
            // remaining replacements is safe and avoids requiring a pristine
            // Recovery backup for every mapping update. Do not overwrite the
            // existing uninstall backup with this already-patched intermediate set.
            bool moduleAlreadyPatched = false;
            bool moduleNeedsPatch = false;
            for (int index = 0; index < modules.Count; index++)
            {
                if (modules[index].AlreadyJapaneseCount >= PartialPatchDetectionThreshold)
                    moduleAlreadyPatched = true;
                if (modules[index].ReplaceCount >= PartialPatchDetectionThreshold)
                    moduleNeedsPatch = true;
            }
            bool incrementalPatch = moduleAlreadyPatched && moduleNeedsPatch;
            if (!incrementalPatch)
                BackupCurrentSet(recoveryRoot, manifestPath, manifest);

            for (int index = 0; index < modules.Count; index++)
            {
                ModulePatch module = modules[index];
                Dictionary<string, object> record = FindModule(manifest, module.LogicalModule);
                record["payload_size"] = (long)module.Patched.LongLength;
                record["payload_sha256"] = Sha256(module.Patched);
            }
            manifest["compiled_identity_sha256"] = ComputeCompiledIdentity(manifest);

            string manifestJson = SerializeJson(manifest);
            List<string> tempFiles = new List<string>();
            try
            {
                for (int index = 0; index < modules.Count; index++)
                {
                    ModulePatch module = modules[index];
                    string temp = module.PayloadPath + ".ro3-ja-tmp";
                    File.WriteAllBytes(temp, module.Patched);
                    tempFiles.Add(temp);
                }
                string manifestTemp = manifestPath + ".ro3-ja-tmp";
                File.WriteAllText(manifestTemp, manifestJson, new UTF8Encoding(false));
                tempFiles.Add(manifestTemp);

                for (int index = 0; index < modules.Count; index++)
                {
                    ReplaceFile(tempFiles[index], modules[index].PayloadPath);
                }
                ReplaceFile(manifestTemp, manifestPath);
            }
            finally
            {
                for (int index = 0; index < tempFiles.Count; index++)
                {
                    try
                    {
                        if (File.Exists(tempFiles[index])) File.Delete(tempFiles[index]);
                    }
                    catch
                    {
                    }
                }
            }

            WritePatchState(manifestPath, mappingPath);
            return FormatStatus(
                incrementalPatch
                    ? "incrementally patched before Lua localization load"
                    : "patched before Lua localization load",
                modules);
        }

        private static Dictionary<long, LocalizationEntry> LoadCanonicalMap(string path)
        {
            Dictionary<long, LocalizationEntry> result = new Dictionary<long, LocalizationEntry>();
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            for (int index = 0; index < lines.Length; index++)
            {
                string line = lines[index];
                if (index == 0) line = line.TrimStart('\ufeff');
                if (String.IsNullOrEmpty(line) || line[0] == '#') continue;
                string[] parts = line.Split('\t');
                if (parts.Length != 3) continue;
                long id;
                if (!Int64.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out id))
                    continue;
                string english = parts[1];
                string japanese = parts[2];
                if (String.IsNullOrEmpty(english) || String.IsNullOrEmpty(japanese) || english == japanese)
                    continue;
                LocalizationEntry existing;
                if (result.TryGetValue(id, out existing))
                {
                    if (existing.English != english || existing.Japanese != japanese)
                        throw new InvalidDataException("Conflicting canonical localization mapping: " + id);
                    continue;
                }
                result.Add(id, new LocalizationEntry { English = english, Japanese = japanese });
            }
            if (result.Count < MinimumExpectedCanonicalEntries)
            {
                throw new InvalidDataException(
                    "Canonical localization mapping is unexpectedly small: " + result.Count);
            }
            return result;
        }

        private static ModulePatch PrepareModule(
            string logicalModule,
            string payloadPath,
            byte[] original,
            Dictionary<long, LocalizationEntry> mapping,
            bool verifyEnglish)
        {
            Dictionary<long, List<Candidate>> candidates =
                new Dictionary<long, List<Candidate>>();
            Dictionary<string, List<LuaStringLocation>> stringLocations =
                new Dictionary<string, List<LuaStringLocation>>(StringComparer.Ordinal);
            ParseLuaChunk(original, delegate(List<LuaConstant> constants)
            {
                for (int index = 0; index < constants.Count; index++)
                {
                    LuaStringLocation location = constants[index].String;
                    if (location == null) continue;
                    string value;
                    try
                    {
                        value = StrictUtf8.GetString(DecodeRo3String(location.Cipher));
                    }
                    catch (DecoderFallbackException)
                    {
                        continue;
                    }
                    List<LuaStringLocation> locations;
                    if (!stringLocations.TryGetValue(value, out locations))
                    {
                        locations = new List<LuaStringLocation>();
                        stringLocations.Add(value, locations);
                    }
                    locations.Add(location);
                }

                for (int index = 0; index + 1 < constants.Count; index++)
                {
                    LuaConstant idConstant = constants[index];
                    LuaConstant stringConstant = constants[index + 1];
                    if (!idConstant.HasInteger || stringConstant.String == null) continue;
                    LocalizationEntry name;
                    if (!mapping.TryGetValue(idConstant.Integer, out name)) continue;
                    string decoded;
                    try
                    {
                        decoded = StrictUtf8.GetString(DecodeRo3String(stringConstant.String.Cipher));
                    }
                    catch (DecoderFallbackException)
                    {
                        continue;
                    }
                    string english = NormalizePayloadText(name.English);
                    string japanese = NormalizePayloadText(name.Japanese);
                    if (verifyEnglish && decoded != english && decoded != japanese)
                        continue;
                    List<Candidate> list;
                    if (!candidates.TryGetValue(idConstant.Integer, out list))
                    {
                        list = new List<Candidate>();
                        candidates.Add(idConstant.Integer, list);
                    }
                    list.Add(new Candidate
                    {
                        Id = idConstant.Integer,
                        Location = stringConstant.String,
                        Decoded = decoded,
                    });
                }
            });

            List<Replacement> replacements = new List<Replacement>();
            HashSet<int> directHandledStarts = new HashSet<int>();
            int alreadyJapanese = 0;
            foreach (KeyValuePair<long, List<Candidate>> pair in candidates)
            {
                if (pair.Value.Count != 1)
                {
                    throw new InvalidDataException(
                        logicalModule + " has ambiguous LanguageKV ID " +
                        pair.Key + " (candidates=" + pair.Value.Count + ").");
                }
                Candidate candidate = pair.Value[0];
                LocalizationEntry name = mapping[pair.Key];
                string japanese = NormalizePayloadText(name.Japanese);
                directHandledStarts.Add(candidate.Location.LengthStart);
                if (candidate.Decoded == japanese)
                {
                    alreadyJapanese++;
                    continue;
                }
                byte[] encoded = EncodeRo3String(Encoding.UTF8.GetBytes(japanese));
                byte[] length = EncodeVarint(encoded.Length + 1);
                byte[] blob = new byte[length.Length + encoded.Length];
                Buffer.BlockCopy(length, 0, blob, 0, length.Length);
                Buffer.BlockCopy(encoded, 0, blob, length.Length, encoded.Length);
                replacements.Add(new Replacement
                {
                    Start = candidate.Location.LengthStart,
                    End = candidate.Location.PayloadEnd,
                    Bytes = blob,
                });
            }

            int directCandidateCount = replacements.Count + alreadyJapanese;
            if (directCandidateCount < MinimumExpectedDirectEntries)
            {
                throw new InvalidDataException(
                    logicalModule + " direct localization candidates are unexpectedly small: " +
                    directCandidateCount);
            }

            int monsterNameCandidateCount = 0;
            if (verifyEnglish)
            {
                monsterNameCandidateCount = AddMonsterNameFallbackReplacements(
                    mapping,
                    stringLocations,
                    directHandledStarts,
                    replacements,
                    ref alreadyJapanese);
                if (monsterNameCandidateCount < MinimumExpectedMonsterNames)
                {
                    throw new InvalidDataException(
                        logicalModule + " monster-name candidates are unexpectedly small: " +
                        monsterNameCandidateCount);
                }
            }

            byte[] patched = ApplyReplacements(original, replacements);
            ParseLuaChunk(patched, null);
            return new ModulePatch
            {
                LogicalModule = logicalModule,
                PayloadPath = payloadPath,
                Original = original,
                Patched = patched,
                ReplaceCount = replacements.Count,
                AlreadyJapaneseCount = alreadyJapanese,
                CandidateCount = replacements.Count + alreadyJapanese,
                MonsterNameCandidateCount = monsterNameCandidateCount,
            };
        }

        private static int AddMonsterNameFallbackReplacements(
            Dictionary<long, LocalizationEntry> mapping,
            Dictionary<string, List<LuaStringLocation>> stringLocations,
            HashSet<int> directHandledStarts,
            List<Replacement> replacements,
            ref int alreadyJapanese)
        {
            Dictionary<string, string> monsterNames =
                new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (KeyValuePair<long, LocalizationEntry> pair in mapping)
            {
                string id = pair.Key.ToString(CultureInfo.InvariantCulture);
                if (!id.StartsWith(MonsterNameIdPrefix, StringComparison.Ordinal)) continue;
                string english = NormalizePayloadText(pair.Value.English);
                string japanese = NormalizePayloadText(pair.Value.Japanese);
                string existing;
                if (monsterNames.TryGetValue(english, out existing))
                {
                    if (!String.Equals(existing, japanese, StringComparison.Ordinal))
                    {
                        throw new InvalidDataException(
                            "Conflicting canonical monster-name translation: " + english);
                    }
                    continue;
                }
                monsterNames.Add(english, japanese);
            }

            // These monster-name strings are shared by other LanguageKV IDs in the
            // compiled localization chunk. Replacing the one shared constant is safe
            // only when every canonical occurrence of that English value resolves to
            // the same Japanese text. Fail closed if a future translation introduces
            // a context-specific conflict.
            foreach (KeyValuePair<long, LocalizationEntry> pair in mapping)
            {
                string english = NormalizePayloadText(pair.Value.English);
                string monsterJapanese;
                if (!monsterNames.TryGetValue(english, out monsterJapanese)) continue;
                string japanese = NormalizePayloadText(pair.Value.Japanese);
                if (!String.Equals(monsterJapanese, japanese, StringComparison.Ordinal))
                {
                    throw new InvalidDataException(
                        "Canonical monster-name text is shared with a conflicting translation: " +
                        english + " (id=" + pair.Key + ").");
                }
            }

            for (int index = 0; index < KnownMonsterNameProbes.Length; index++)
            {
                if (!monsterNames.ContainsKey(KnownMonsterNameProbes[index]))
                {
                    throw new InvalidDataException(
                        "Known canonical monster-name probe is missing: " +
                        KnownMonsterNameProbes[index]);
                }
            }

            HashSet<int> usedStarts = new HashSet<int>();
            for (int index = 0; index < replacements.Count; index++)
                usedStarts.Add(replacements[index].Start);

            int covered = 0;
            foreach (KeyValuePair<string, string> pair in monsterNames)
            {
                List<LuaStringLocation> englishLocations;
                List<LuaStringLocation> japaneseLocations;
                int englishCount = stringLocations.TryGetValue(pair.Key, out englishLocations)
                    ? englishLocations.Count
                    : 0;
                int japaneseCount = stringLocations.TryGetValue(pair.Value, out japaneseLocations)
                    ? japaneseLocations.Count
                    : 0;

                if (englishCount == 0 && japaneseCount >= 1)
                {
                    bool hasFallbackJapaneseLocation = false;
                    for (int index = 0; index < japaneseLocations.Count; index++)
                    {
                        if (!directHandledStarts.Contains(japaneseLocations[index].LengthStart))
                        {
                            hasFallbackJapaneseLocation = true;
                            break;
                        }
                    }
                    if (hasFallbackJapaneseLocation)
                    {
                        alreadyJapanese++;
                    }
                    covered++;
                    continue;
                }
                if (englishCount == 1 && japaneseCount > 0)
                {
                    bool allJapaneseDirectHandled = true;
                    for (int index = 0; index < japaneseLocations.Count; index++)
                    {
                        if (!directHandledStarts.Contains(japaneseLocations[index].LengthStart))
                        {
                            allJapaneseDirectHandled = false;
                            break;
                        }
                    }
                    if (!allJapaneseDirectHandled)
                    {
                        throw new InvalidDataException(
                            "Ambiguous Recovery monster-name constant " + pair.Key +
                            " (english=" + englishCount + ", japanese=" + japaneseCount + ").");
                    }
                }
                else if (englishCount != 1 || japaneseCount != 0)
                {
                    throw new InvalidDataException(
                        "Ambiguous Recovery monster-name constant " + pair.Key +
                        " (english=" + englishCount + ", japanese=" + japaneseCount + ").");
                }

                LuaStringLocation location = englishLocations[0];
                if (directHandledStarts.Contains(location.LengthStart))
                {
                    covered++;
                    continue;
                }
                if (!usedStarts.Add(location.LengthStart))
                {
                    throw new InvalidDataException(
                        "Monster-name fallback overlaps a direct localization replacement: " + pair.Key);
                }
                byte[] encoded = EncodeRo3String(Encoding.UTF8.GetBytes(pair.Value));
                byte[] length = EncodeVarint(encoded.Length + 1);
                byte[] blob = new byte[length.Length + encoded.Length];
                Buffer.BlockCopy(length, 0, blob, 0, length.Length);
                Buffer.BlockCopy(encoded, 0, blob, length.Length, encoded.Length);
                replacements.Add(new Replacement
                {
                    Start = location.LengthStart,
                    End = location.PayloadEnd,
                    Bytes = blob,
                });
                covered++;
            }
            return covered;
        }

        private static string NormalizePayloadText(string value)
        {
            return (value ?? String.Empty).Replace("\\n", "\n");
        }

        private static void ParseLuaChunk(byte[] data, Action<List<LuaConstant>> constantsVisitor)
        {
            LuaReader reader = new LuaReader(data);
            byte[] signature = reader.ReadBytes(4);
            if (signature[0] != 0x1e || signature[1] != (byte)'L' ||
                signature[2] != (byte)'u' || signature[3] != (byte)'a')
                throw new InvalidDataException("Not an RO3 Lua payload.");
            if (reader.ReadByte() != 0x54 || reader.ReadByte() != 0)
                throw new InvalidDataException("Unexpected Lua version/format.");
            byte[] luacData = reader.ReadBytes(6);
            byte[] expectedLuac = { 0x19, 0x93, 0x0d, 0x0a, 0x1a, 0x0a };
            for (int i = 0; i < expectedLuac.Length; i++)
                if (luacData[i] != expectedLuac[i])
                    throw new InvalidDataException("Unexpected Lua signature data.");
            if (reader.ReadByte() != 4 || reader.ReadByte() != 8 || reader.ReadByte() != 8)
                throw new InvalidDataException("Unexpected Lua primitive sizes.");
            if (reader.ReadInt64() != 0x5678)
                throw new InvalidDataException("Unexpected LUAC_INT.");
            if (Math.Abs(reader.ReadDouble() - 370.5) > 0.000001)
                throw new InvalidDataException("Unexpected LUAC_NUM.");
            reader.ReadByte();
            ParseProto(reader, constantsVisitor);
            if (reader.Position != reader.Length)
                throw new InvalidDataException(
                    "Lua parser did not consume the payload: " +
                    reader.Position + " != " + reader.Length);
        }

        private static void ParseProto(LuaReader reader, Action<List<LuaConstant>> constantsVisitor)
        {
            reader.ReadLuaString();
            reader.ReadVarint();
            reader.ReadVarint();
            reader.ReadByte();
            reader.ReadByte();
            reader.ReadByte();

            int codeCount = reader.ReadVarint();
            reader.Skip(checked(codeCount * 4));

            int constantCount = reader.ReadVarint();
            List<LuaConstant> constants = new List<LuaConstant>(constantCount);
            for (int index = 0; index < constantCount; index++)
            {
                int tag = reader.ReadByte();
                LuaConstant constant = new LuaConstant { Tag = tag };
                switch (tag)
                {
                    case 0:
                        break;
                    case 1:
                    case 17:
                        break;
                    case 3:
                        constant.Integer = reader.ReadInt64();
                        constant.HasInteger = true;
                        break;
                    case 19:
                        reader.ReadDouble();
                        break;
                    case 4:
                    case 20:
                        constant.String = reader.ReadLuaString();
                        break;
                    default:
                        throw new InvalidDataException("Unknown Lua constant tag: " + tag);
                }
                constants.Add(constant);
            }
            if (constantsVisitor != null) constantsVisitor(constants);

            int upvalueCount = reader.ReadVarint();
            reader.Skip(checked(upvalueCount * 3));
            int childCount = reader.ReadVarint();
            for (int index = 0; index < childCount; index++)
                ParseProto(reader, constantsVisitor);

            int lineInfoCount = reader.ReadVarint();
            reader.Skip(lineInfoCount);
            int absLineCount = reader.ReadVarint();
            for (int index = 0; index < absLineCount; index++)
            {
                reader.ReadVarint();
                reader.ReadVarint();
            }
            int localCount = reader.ReadVarint();
            for (int index = 0; index < localCount; index++)
            {
                reader.ReadLuaString();
                reader.ReadVarint();
                reader.ReadVarint();
            }
            int upvalueNameCount = reader.ReadVarint();
            for (int index = 0; index < upvalueNameCount; index++)
                reader.ReadLuaString();
        }

        private static byte[] DecodeRo3String(byte[] cipher)
        {
            if (cipher.Length == 0) return new byte[0];
            byte[] plain = new byte[cipher.Length];
            plain[0] = (byte)(cipher[0] ^ cipher.Length);
            for (int index = 1; index < cipher.Length; index++)
                plain[index] = (byte)(cipher[index] ^ cipher[index - 1]);
            return plain;
        }

        private static byte[] EncodeRo3String(byte[] plain)
        {
            if (plain.Length == 0) return new byte[0];
            byte[] cipher = new byte[plain.Length];
            cipher[0] = (byte)(plain[0] ^ plain.Length);
            for (int index = 1; index < plain.Length; index++)
                cipher[index] = (byte)(plain[index] ^ cipher[index - 1]);
            return cipher;
        }

        private static byte[] EncodeVarint(int value)
        {
            List<byte> groups = new List<byte>();
            groups.Add((byte)(value & 0x7f));
            value >>= 7;
            while (value != 0)
            {
                groups.Add((byte)(value & 0x7f));
                value >>= 7;
            }
            groups.Reverse();
            groups[groups.Count - 1] = (byte)(groups[groups.Count - 1] | 0x80);
            return groups.ToArray();
        }

        private static byte[] ApplyReplacements(byte[] original, List<Replacement> replacements)
        {
            replacements.Sort(delegate(Replacement left, Replacement right)
            {
                return left.Start.CompareTo(right.Start);
            });
            using (MemoryStream output = new MemoryStream(original.Length + 32768))
            {
                int cursor = 0;
                for (int index = 0; index < replacements.Count; index++)
                {
                    Replacement replacement = replacements[index];
                    if (replacement.Start < cursor || replacement.End < replacement.Start ||
                        replacement.End > original.Length)
                        throw new InvalidDataException("Overlapping or invalid Lua replacement.");
                    output.Write(original, cursor, replacement.Start - cursor);
                    output.Write(replacement.Bytes, 0, replacement.Bytes.Length);
                    cursor = replacement.End;
                }
                output.Write(original, cursor, original.Length - cursor);
                return output.ToArray();
            }
        }

        private static Dictionary<string, object> ParseManifest(string path)
        {
            object root = new JsonParser(File.ReadAllText(path, Encoding.UTF8)).Parse();
            Dictionary<string, object> manifest = root as Dictionary<string, object>;
            if (manifest == null) throw new InvalidDataException("Recovery manifest root is not an object.");
            return manifest;
        }

        private static void ValidateManifestIdentity(Dictionary<string, object> manifest)
        {
            string expected = GetString(manifest, "compiled_identity_sha256");
            string actual = ComputeCompiledIdentity(manifest);
            if (!String.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Recovery manifest compiled identity is inconsistent.");
        }

        private static Dictionary<string, object> FindModule(
            Dictionary<string, object> manifest,
            string logicalModule)
        {
            List<object> modules = GetArray(manifest, "modules");
            for (int index = 0; index < modules.Count; index++)
            {
                Dictionary<string, object> record = modules[index] as Dictionary<string, object>;
                if (record != null &&
                    String.Equals(GetOptionalString(record, "logical_module"), logicalModule,
                        StringComparison.Ordinal))
                    return record;
            }
            throw new InvalidDataException("Recovery module is missing: " + logicalModule);
        }

        private static string ComputeCompiledIdentity(Dictionary<string, object> manifest)
        {
            int schema = checked((int)GetInt64(manifest, "schema_version"));
            using (MemoryStream stream = new MemoryStream())
            using (BinaryWriter writer = new BinaryWriter(stream, new UTF8Encoding(false)))
            {
                byte[] magic = Encoding.ASCII.GetBytes(
                    schema == 3 ? "RO3RECOVERYBUILD1\0" : "RO3RECOVERYBUILD2\0");
                writer.Write(magic);
                WriteIdentityString(writer, GetOptionalString(manifest, "build_variant"));
                WriteIdentityString(writer, GetOptionalString(manifest, "lua_source_kind"));
                if (schema != 3)
                {
                    WriteIdentityString(writer, GetOptionalString(manifest, "build_target"));
                    WriteIdentityString(writer, GetOptionalString(manifest, "cpu_abi"));
                    WriteIdentityString(writer, GetOptionalString(manifest, "scripting_backend"));
                    WriteIdentityString(writer, GetOptionalString(manifest, "application_identifier"));
                }
                WriteIdentityString(writer, GetOptionalString(manifest, "compiler_evidence_id"));
                WriteIdentityString(writer, GetOptionalString(manifest, "approved_player_xlua_sha256"));
                WriteIdentityString(writer, GetOptionalString(manifest, "release_config_evidence_sha256"));
                WriteIdentityString(writer, GetOptionalString(manifest, "release_config_overlay_membership_sha256"));

                List<Dictionary<string, object>> modules = new List<Dictionary<string, object>>();
                List<object> rawModules = GetArray(manifest, "modules");
                for (int index = 0; index < rawModules.Count; index++)
                {
                    Dictionary<string, object> record = rawModules[index] as Dictionary<string, object>;
                    if (record != null) modules.Add(record);
                }
                modules.Sort(delegate(Dictionary<string, object> left, Dictionary<string, object> right)
                {
                    return StringComparer.Ordinal.Compare(
                        GetOptionalString(left, "logical_module") ?? String.Empty,
                        GetOptionalString(right, "logical_module") ?? String.Empty);
                });
                string[] fields =
                {
                    "logical_module",
                    "source_sha256",
                    "payload_sha256",
                    "compiler_evidence_id",
                    "selected_provider",
                    "source_authority",
                    "source_evidence_id",
                };
                for (int moduleIndex = 0; moduleIndex < modules.Count; moduleIndex++)
                {
                    for (int fieldIndex = 0; fieldIndex < fields.Length; fieldIndex++)
                        WriteIdentityString(writer, GetOptionalString(modules[moduleIndex], fields[fieldIndex]));
                }
                writer.Flush();
                return Sha256(stream.ToArray());
            }
        }

        private static void WriteIdentityString(BinaryWriter writer, string value)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(value ?? String.Empty);
            writer.Write(bytes.Length);
            writer.Write(bytes);
        }

        private static void BackupCurrentSet(
            string recoveryRoot,
            string manifestPath,
            Dictionary<string, object> manifest)
        {
            // Overwrite backups only when the current manifest/payloads were already
            // verified as a coherent pre-patch set. This makes a later game update
            // refresh the uninstall backup instead of retaining stale game files.
            File.Copy(manifestPath, manifestPath + BackupSuffix, true);
            for (int index = 0; index < TargetModules.Length; index++)
            {
                Dictionary<string, object> record = FindModule(manifest, TargetModules[index]);
                string payload = Path.Combine(
                    recoveryRoot, "LuaPayload", GetString(record, "payload_relative_path"));
                File.Copy(payload, payload + BackupSuffix, true);
            }
        }

        private static bool TryRestoreSameBuildBackups(
            string recoveryRoot,
            string manifestPath,
            Dictionary<string, object> currentManifest)
        {
            string backupManifestPath = manifestPath + BackupSuffix;
            if (!File.Exists(backupManifestPath)) return false;
            Dictionary<string, object> backupManifest;
            try
            {
                backupManifest = ParseManifest(backupManifestPath);
                ValidateManifestIdentity(backupManifest);
                for (int index = 0; index < TargetModules.Length; index++)
                {
                    Dictionary<string, object> currentRecord =
                        FindModule(currentManifest, TargetModules[index]);
                    Dictionary<string, object> backupRecord =
                        FindModule(backupManifest, TargetModules[index]);
                    if (!String.Equals(
                            GetOptionalString(currentRecord, "source_sha256"),
                            GetOptionalString(backupRecord, "source_sha256"),
                            StringComparison.OrdinalIgnoreCase))
                        return false;
                    string backupPayload = Path.Combine(
                        recoveryRoot,
                        "LuaPayload",
                        GetString(backupRecord, "payload_relative_path")) + BackupSuffix;
                    if (!File.Exists(backupPayload)) return false;
                    byte[] bytes = File.ReadAllBytes(backupPayload);
                    if (bytes.LongLength != GetInt64(backupRecord, "payload_size") ||
                        !String.Equals(Sha256(bytes), GetString(backupRecord, "payload_sha256"),
                            StringComparison.OrdinalIgnoreCase))
                        return false;
                }

                for (int index = 0; index < TargetModules.Length; index++)
                {
                    Dictionary<string, object> record = FindModule(backupManifest, TargetModules[index]);
                    string payload = Path.Combine(
                        recoveryRoot, "LuaPayload", GetString(record, "payload_relative_path"));
                    File.Copy(payload + BackupSuffix, payload, true);
                }
                File.Copy(backupManifestPath, manifestPath, true);
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static void ReplaceFile(string tempPath, string destinationPath)
        {
            // File.Replace is atomic on the target NTFS volume.  Fall back to a
            // normal overwrite for Mono/filesystem combinations that do not expose it.
            try
            {
                File.Replace(tempPath, destinationPath, null);
            }
            catch (PlatformNotSupportedException)
            {
                File.Copy(tempPath, destinationPath, true);
                File.Delete(tempPath);
            }
            catch (IOException)
            {
                File.Copy(tempPath, destinationPath, true);
                File.Delete(tempPath);
            }
        }

        private static void WritePatchState(string manifestPath, string mappingPath)
        {
            string configDirectory = Path.GetDirectoryName(mappingPath);
            if (String.IsNullOrEmpty(configDirectory))
                throw new InvalidDataException("Localization mapping has no config directory.");

            string statePath = Path.Combine(configDirectory, "RO3.RecoveryPatchState.txt");
            string tempPath = statePath + ".tmp";
            string manifestHash = Sha256(File.ReadAllBytes(manifestPath));
            string content =
                "RO3_RECOVERY_PATCH=1\r\n" +
                "PATCHED_MANIFEST_SHA256=" + manifestHash + "\r\n";
            File.WriteAllText(tempPath, content, new UTF8Encoding(false));
            ReplaceFile(tempPath, statePath);
        }

        private static string FormatStatus(string action, List<ModulePatch> modules)
        {
            StringBuilder result = new StringBuilder(action);
            for (int index = 0; index < modules.Count; index++)
            {
                ModulePatch module = modules[index];
                result.Append(index == 0 ? ": " : ", ");
                result.Append(module.LogicalModule);
                result.Append(" replace=");
                result.Append(module.ReplaceCount);
                result.Append(" alreadyJapanese=");
                result.Append(module.AlreadyJapaneseCount);
                result.Append(" candidates=");
                result.Append(module.CandidateCount);
                if (module.MonsterNameCandidateCount > 0)
                {
                    result.Append(" monsterNames=");
                    result.Append(module.MonsterNameCandidateCount);
                }
            }
            return result.ToString();
        }

        private static string Sha256(byte[] bytes)
        {
            using (SHA256 sha = SHA256.Create())
            {
                byte[] hash = sha.ComputeHash(bytes);
                StringBuilder text = new StringBuilder(hash.Length * 2);
                for (int index = 0; index < hash.Length; index++)
                    text.Append(hash[index].ToString("x2", CultureInfo.InvariantCulture));
                return text.ToString();
            }
        }

        private static long GetInt64(Dictionary<string, object> obj, string key)
        {
            object value;
            if (!obj.TryGetValue(key, out value) || value == null)
                throw new InvalidDataException("Missing JSON integer: " + key);
            if (value is long) return (long)value;
            if (value is double) return checked((long)(double)value);
            return Convert.ToInt64(value, CultureInfo.InvariantCulture);
        }

        private static string GetString(Dictionary<string, object> obj, string key)
        {
            string value = GetOptionalString(obj, key);
            if (value == null) throw new InvalidDataException("Missing JSON string: " + key);
            return value;
        }

        private static string GetOptionalString(Dictionary<string, object> obj, string key)
        {
            object value;
            if (!obj.TryGetValue(key, out value) || value == null) return null;
            string text = value as string;
            if (text == null) throw new InvalidDataException("JSON field is not a string: " + key);
            return text;
        }

        private static List<object> GetArray(Dictionary<string, object> obj, string key)
        {
            object value;
            if (!obj.TryGetValue(key, out value))
                throw new InvalidDataException("Missing JSON array: " + key);
            List<object> array = value as List<object>;
            if (array == null) throw new InvalidDataException("JSON field is not an array: " + key);
            return array;
        }

        private static string SerializeJson(object value)
        {
            StringBuilder output = new StringBuilder(16 * 1024 * 1024);
            WriteJsonValue(output, value);
            output.Append('\n');
            return output.ToString();
        }

        private static void WriteJsonValue(StringBuilder output, object value)
        {
            if (value == null)
            {
                output.Append("null");
                return;
            }
            string text = value as string;
            if (text != null)
            {
                WriteJsonString(output, text);
                return;
            }
            if (value is bool)
            {
                output.Append((bool)value ? "true" : "false");
                return;
            }
            Dictionary<string, object> obj = value as Dictionary<string, object>;
            if (obj != null)
            {
                output.Append('{');
                bool first = true;
                foreach (KeyValuePair<string, object> pair in obj)
                {
                    if (!first) output.Append(',');
                    first = false;
                    WriteJsonString(output, pair.Key);
                    output.Append(':');
                    WriteJsonValue(output, pair.Value);
                }
                output.Append('}');
                return;
            }
            List<object> array = value as List<object>;
            if (array != null)
            {
                output.Append('[');
                for (int index = 0; index < array.Count; index++)
                {
                    if (index != 0) output.Append(',');
                    WriteJsonValue(output, array[index]);
                }
                output.Append(']');
                return;
            }
            if (value is double)
            {
                output.Append(((double)value).ToString("R", CultureInfo.InvariantCulture));
                return;
            }
            output.Append(Convert.ToString(value, CultureInfo.InvariantCulture));
        }

        private static void WriteJsonString(StringBuilder output, string value)
        {
            output.Append('"');
            for (int index = 0; index < value.Length; index++)
            {
                char current = value[index];
                switch (current)
                {
                    case '"': output.Append("\\\""); break;
                    case '\\': output.Append("\\\\"); break;
                    case '\b': output.Append("\\b"); break;
                    case '\f': output.Append("\\f"); break;
                    case '\n': output.Append("\\n"); break;
                    case '\r': output.Append("\\r"); break;
                    case '\t': output.Append("\\t"); break;
                    default:
                        if (current < 0x20)
                        {
                            output.Append("\\u");
                            output.Append(((int)current).ToString("x4", CultureInfo.InvariantCulture));
                        }
                        else
                        {
                            output.Append(current);
                        }
                        break;
                }
            }
            output.Append('"');
        }
    }
}

# Read-only diagnostic: exercise shipping .NET regex rules without a game process.
param([switch]$Details, [switch]$Verify, [string]$Case = '', [string]$CasePrefix = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
# Mirrors TextHelper.ReadTranslationLineAndDecode in the installed XUnity DLL.
# Only local strings are parsed; no plugin or game code is executed.
$testSource = @'
using System;
using System.Text;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Reflection;
public static class HistoryTranslationLine {
    public static string[] Decode(string line) {
        return RO3.JapaneseMod.DisplayTextTranslator.DecodeDictionaryLine(line);
    }
}
public static class HistoryCheck {
    public static int Run(string repo, string caseFilter, string casePrefix) {
        var translator = new RO3.JapaneseMod.DisplayTextTranslator();
        var ids = new Dictionary<string, string>();
        foreach (var line in File.ReadAllLines(Path.Combine(repo, "Client/BepInEx/config/RO3.LocalizationOverrides.tsv"))) {
            var fields = line.TrimStart('\uFEFF').Split(new[] {'\t'}, 3);
            if (fields.Length != 3 || fields[0].StartsWith("#")) continue;
            translator.Add(fields[0], fields[1], fields[2]); ids[fields[0]] = fields[2].Replace(@"\n", "\n");
        }
        foreach (var line in File.ReadAllLines(Path.Combine(repo, "Client/BepInEx/config/RO3.LocalizationAliases.tsv"))) {
            var fields = line.TrimStart('\uFEFF').Split(new[] {'\t'}, 3);
            if (fields.Length == 3 && !fields[0].StartsWith("#")) translator.Add(fields[0], fields[1], fields[2]);
        }
        var exact = new Dictionary<string, string>(StringComparer.Ordinal);
        var rules = new List<KeyValuePair<Regex, string>>();
        int failed = 0, total = 0;
        foreach (string file in new[] {"RO3_CanonicalTranslations.txt", "RO3_PriorityOverrides.txt", "RO3_RuntimePlaceholders.txt"}) {
            foreach (var line in File.ReadAllLines(Path.Combine(repo, "Client/BepInEx/Translation/ja/Text/" + file))) {
                if (String.IsNullOrEmpty(line) || line.StartsWith("//")) continue;
                total++;
                var pair = HistoryTranslationLine.Decode(line);
                if (pair == null) { Console.WriteLine("FAILED: dictionary decode " + file); failed++; continue; }
                if (pair[0].StartsWith("r:\""))
                    rules.Add(new KeyValuePair<Regex, string>(new Regex(pair[0].Substring(3, pair[0].Length - 4), RegexOptions.None, TimeSpan.FromMilliseconds(100)), pair[1]));
                else { exact[pair[0]] = pair[1]; translator.AddOfflineExact(pair[0], pair[1]); }
            }
        }
        translator.OfflineLookup = delegate(string input) {
            string value;
            if (exact.TryGetValue(input, out value)) return value;
            for (int i = rules.Count - 1; i >= 0; i--)
                if (rules[i].Key.IsMatch(input)) return rules[i].Key.Replace(input, rules[i].Value);
            return null;
        };
        if (caseFilter.Length == 0 && (casePrefix.Length == 0 || casePrefix.StartsWith("exact:", StringComparison.Ordinal))) {
            foreach (var pair in exact) {
                if (casePrefix.Length != 0 && !pair.Key.StartsWith(casePrefix.Substring(6), StringComparison.Ordinal)) continue;
                if (Regex.IsMatch(pair.Key, @"[$@^]?\{[0-9]+\}")) continue;
                total++;
                string actual = translator.Translate(pair.Key);
                if (actual != pair.Value || translator.Translate(actual) != actual) {
                    failed++;
                    if (failed <= 12) Console.WriteLine("FAILED: exact dictionary " + pair.Key + "\nexpected=" + pair.Value + "\nactual=" + actual + "\nsecond=" + translator.Translate(actual));
                }
            }
        }
        var previouslyMissingRules = new HashSet<string>(new[] {"10960000082", "10960000083", "12390100342", "10050100004", "40310", "25163", "25164", "25172", "25173", "25174", "25175", "25176", "50058", "50059", "34076", "35031"});
        foreach (var line in File.ReadAllLines(Path.Combine(repo, "scripts/history-regression-cases.tsv"))) {
            var fields = line.Split(new[] {'\t'}, 3);
            if (caseFilter.Length != 0 && fields[0] != caseFilter) continue;
            if (casePrefix.Length != 0 && !fields[0].StartsWith(casePrefix, StringComparison.Ordinal)) continue;
            string expected = fields[2].Replace(@"\n", "\n");
            if (fields[0].StartsWith("text:") && previouslyMissingRules.Contains(fields[0].Substring(5))) {
                total++;
                string input = fields[1].Replace(@"\n", "\n");
                if (!rules.Exists(rule => rule.Key.IsMatch(input) && rule.Key.Replace(input, rule.Value) == expected)) {
                    failed++; Console.WriteLine("FAILED: rendered dictionary " + fields[0] + " - scripts/history-regression-cases.tsv");
                }
            }
            string actual = fields[0].StartsWith("id:") ? ids[fields[0].Substring(3)] : translator.Translate(fields[1].Replace(@"\n", "\n"));
            total++;
            if (actual != expected || (!fields[0].StartsWith("id:") && translator.Translate(actual) != actual)) {
                failed++; Console.WriteLine("FAILED: " + fields[0] + " - scripts/history-regression-cases.tsv");
                if (caseFilter.Length != 0 || failed <= 12) Console.WriteLine("input=" + fields[1] + "\nexpected=" + expected + "\nactual=" + actual + "\nsecond=" + translator.Translate(actual));
            }
        }
        Console.WriteLine("Tests: " + total + " total, " + (total-failed) + " passed, " + failed + " failed");
        return failed == 0 ? 0 : 1;
    }
}
'@
$displaySource = [IO.File]::ReadAllText((Join-Path $repo 'src/RO3.LocalizationTablePatcher/DisplayTextTranslator.cs'))
Add-Type -TypeDefinition ($testSource + [regex]::Replace($displaySource, '(?m)^using .*;\r?\n', ''))
if ($null -ne [HistoryTranslationLine]::Decode('<color=#fff>A</color>=B')) { throw 'Parser guard failed' }
if ([HistoryTranslationLine]::Decode('<color\=#fff>A</color>=B')[0] -cne '<color=#fff>A</color>') { throw 'Escaped delimiter failed' }
if ([HistoryTranslationLine]::Decode('a\\nb=c')[0] -cne 'a\nb') { throw 'Backslash decoding failed' }
if ([HistoryTranslationLine]::Decode('a\u002F\u002Fb=literal\u00253D')[0] -cne 'a//b') { throw 'Comment escape failed' }
if ([HistoryTranslationLine]::Decode('a\u002F\u002Fb=literal\u00253D')[1] -cne 'literal%3D') { throw 'Percent escape failed' }
if ($Verify) { exit [HistoryCheck]::Run($repo, $Case, $CasePrefix) }
$rejected = 0
$dictionary = Join-Path $repo 'Client\BepInEx\Translation\ja\Text\RO3_RuntimePlaceholders.txt'
$rules = foreach ($line in [IO.File]::ReadAllLines($dictionary)) {
    if (!$line.StartsWith('r:"')) { continue }
    $decoded = [HistoryTranslationLine]::Decode($line)
    if ($null -eq $decoded) { $rejected++; continue }
    $pattern = $decoded[0].Substring(3, $decoded[0].Length - 4)
    [pscustomobject]@{
        Pattern = [regex]::new($pattern, [Text.RegularExpressions.RegexOptions]::None, [TimeSpan]::FromMilliseconds(100))
        Replacement = $decoded[1]
    }
}
Write-Output "Runtime rules: loaded=$($rules.Count) rejected=$rejected"
foreach ($name in @('RO3_CanonicalTranslations.txt', 'RO3_PriorityOverrides.txt')) {
    $total = 0; $invalid = 0
    foreach ($line in [IO.File]::ReadAllLines((Join-Path (Split-Path $dictionary) $name))) {
        if (!$line -or $line.StartsWith('//')) { continue }
        $total++
        if ($null -eq [HistoryTranslationLine]::Decode($line)) { $invalid++ }
    }
    Write-Output "$name entries=$total rejected=$invalid"
}
$failures = @('10960000082','10960000083','12390100342','10050100004','40310','25163','25164','25172','25173','25174','25175','25176','50058','50059','34076','35031','pickup','prerequisite')
foreach ($line in [IO.File]::ReadAllLines((Join-Path $PSScriptRoot 'history-regression-cases.tsv'))) {
    $parts = $line.Split([char]9, 3)
    $key = $parts[0].Replace('text:', '')
    if ($key -notin $failures) { continue }
    $inputText = $parts[1].Replace('\n', "`n")
    $expected = $parts[2].Replace('\n', "`n")
    $matching = @($rules | Where-Object { $_.Pattern.IsMatch($inputText) })
    $correct = @($matching | Where-Object { $_.Pattern.Replace($inputText, $_.Replacement) -ceq $expected })
    Write-Output "$key matches=$($matching.Count) canonicalMatches=$($correct.Count)"
    if ($Details) {
        foreach ($rule in $matching) {
            Write-Output ('  actual=' + $rule.Pattern.Replace($inputText, $rule.Replacement).Replace("`n", '\n'))
        }
    }
}

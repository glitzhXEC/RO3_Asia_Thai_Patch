using System;
using System.IO;
using RO3.JapaneseMod;

internal static class EnglishDescriptionAliasTest
{
    private static int Main(string[] args)
    {
        var translator = new DisplayTextTranslator();
        translator.OfflineLookup = delegate(string value) { return "UNEXPECTED_SECOND_TRANSLATION"; };
        var rows = new System.Collections.Generic.List<string[]>();
        foreach (string line in File.ReadAllLines(args[0]))
        {
            string[] fields = line.TrimStart('\uFEFF').Split(new[] { '\t' }, 3);
            if (fields.Length != 3 || fields[0].StartsWith("#")) continue;
            bool description = fields[0].StartsWith("101103") || fields[0].StartsWith("102203")
                || fields[0].StartsWith("108001") || fields[0].StartsWith("123901")
                || fields[0].StartsWith("100501") || fields[0].StartsWith("131500")
                || fields[0].StartsWith("131502") || fields[0].StartsWith("131506");
            if (!description) continue;
            translator.AddTerminalEnglish(fields[1], fields[2]);
            rows.Add(fields);
        }

        int failed = 0;
        foreach (string[] row in rows)
        {
            if (translator.Translate(row[1]) != row[2])
            {
                Console.WriteLine("FAILED: terminal English alias for " + row[0]);
                failed++;
                if (failed == 10) break;
            }
        }
        Console.WriteLine("English Chinese-description aliases: " + (rows.Count - failed) + "/" + rows.Count + " passed");
        return failed == 0 && rows.Count >= 1000 ? 0 : 1;
    }
}

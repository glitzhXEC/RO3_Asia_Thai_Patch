using BepInEx;
using System;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

namespace RO3.JapaneseMod
{
    [BepInPlugin("com.ro3.japanesefont", "RO3 Japanese Font Loader", "1.0.0")]
    public class JapaneseFontPlugin : BaseUnityPlugin
    {
        private static TMP_FontAsset _japaneseTmpFont;
        private static Font _japaneseFont;
        private static bool _addedToSettings = false;

        private void Awake()
        {
            Logger.LogInfo("[JapaneseFont] RO3 Japanese Font Loader plugin Awake!");
            EnsureFont();
        }

        private void Start()
        {
            EnsureFont();
        }

        private void Update()
        {
            if (!_addedToSettings)
            {
                EnsureFont();
            }
        }

        private void EnsureFont()
        {
            try
            {
                if (_japaneseTmpFont == null)
                {
                    string[] fontNames = new string[] { "Yu Gothic UI", "Meiryo", "MS Gothic", "Arial" };
                    _japaneseFont = Font.CreateDynamicFontFromOSFont(fontNames, 28);
                    if (_japaneseFont != null)
                    {
                        DontDestroyOnLoad(_japaneseFont);
                        _japaneseTmpFont = TMP_FontAsset.CreateFontAsset(_japaneseFont);
                        if (_japaneseTmpFont != null)
                        {
                            DontDestroyOnLoad(_japaneseTmpFont);
                            Logger.LogInfo("[JapaneseFont] Successfully created dynamic Japanese TMP_FontAsset from OS font!");
                        }
                    }
                }

                if (_japaneseTmpFont != null)
                {
                    var fallbacks = TMP_Settings.fallbackFontAssets;
                    if (fallbacks != null)
                    {
                        if (!fallbacks.Contains(_japaneseTmpFont))
                        {
                            fallbacks.Add(_japaneseTmpFont);
                            _addedToSettings = true;
                            Logger.LogInfo("[JapaneseFont] Added Japanese TMP_FontAsset to TMP_Settings.fallbackFontAssets! (Count: " + fallbacks.Count + ")");
                        }
                    }

                    // Also check defaultFontAsset fallback list
                    var defaultFont = TMP_Settings.defaultFontAsset;
                    if (defaultFont != null && defaultFont.fallbackFontAssetTable != null)
                    {
                        if (!defaultFont.fallbackFontAssetTable.Contains(_japaneseTmpFont))
                        {
                            defaultFont.fallbackFontAssetTable.Add(_japaneseTmpFont);
                            Logger.LogInfo("[JapaneseFont] Added Japanese TMP_FontAsset to defaultFontAsset.fallbackFontAssetTable!");
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Logger.LogError("[JapaneseFont] Error in EnsureFont: " + ex.Message);
            }
        }
    }
}

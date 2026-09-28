using BepInEx;
using System;
using System.Collections.Generic;
using TMPro;
using UnityEngine;

namespace RO3.JapaneseMod
{
    [BepInPlugin("com.ro3.worldnameplateprobe", "RO3 World Nameplate Probe", "1.0.0")]
    public sealed class WorldNameplateProbe : BaseUnityPlugin
    {
        private readonly HashSet<int> _logged = new HashSet<int>();
        private float _nextScan;

        private void Awake()
        {
            Logger.LogInfo("[WorldNameplateProbe] Awake");
        }

        private void Update()
        {
            if (Time.unscaledTime < _nextScan) return;
            _nextScan = Time.unscaledTime + 0.75f;

            TMP_Text[] texts;
            try { texts = Resources.FindObjectsOfTypeAll<TMP_Text>(); }
            catch (Exception ex)
            {
                Logger.LogError("[WorldNameplateProbe] scan failed: " + ex);
                return;
            }

            foreach (var t in texts)
            {
                if (t == null) continue;
                string value;
                try { value = t.text; }
                catch { continue; }
                if (value != "Magnolia" && value != "Piere") continue;

                int id = t.GetInstanceID();
                if (!_logged.Add(id)) continue;

                Logger.LogInfo(
                    "[WorldNameplateProbe] text='" + value +
                    "' component=" + t.GetType().FullName +
                    " object='" + t.gameObject.name +
                    "' activeSelf=" + t.gameObject.activeSelf +
                    " activeInHierarchy=" + t.gameObject.activeInHierarchy +
                    " path='" + BuildPath(t.transform) + "'");
            }
        }

        private static string BuildPath(Transform t)
        {
            if (t == null) return "<null>";
            var names = new List<string>();
            while (t != null)
            {
                names.Add(t.name);
                t = t.parent;
            }
            names.Reverse();
            return "/" + string.Join("/", names.ToArray());
        }
    }
}
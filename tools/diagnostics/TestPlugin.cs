using System;
using BepInEx;

namespace TestNamespace {
    [BepInPlugin("com.test.plugin", "Test Plugin", "1.0.0")]
    public class TestPlugin : BaseUnityPlugin {
        private void Awake() {
            Logger.LogInfo("Hello from TestPlugin!");
        }
    }
}
"""Compile and exercise terminal Chinese-to-English description lookup."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
compiler = Path(os.environ["WINDIR"]) / "Microsoft.NET/Framework/v4.0.30319/csc.exe"
with tempfile.TemporaryDirectory(prefix="ro3-description-alias-test-") as temp:
    exe = Path(temp) / "test.exe"
    build = subprocess.run(
        [
            str(compiler),
            "/nologo",
            "/codepage:65001",
            "/out:" + str(exe),
            str(root / "src/RO3.LocalizationTablePatcher/DisplayTextTranslator.cs"),
            str(root / "scripts/EnglishDescriptionAliasTest.cs"),
        ],
        capture_output=True,
        text=True,
    )
    if build.returncode:
        print(build.stdout + build.stderr)
        raise SystemExit(build.returncode)
    result = subprocess.run(
        [str(exe), str(root / "Client/BepInEx/config/RO3.LocalizationAliases.tsv")],
        capture_output=True,
        text=True,
        timeout=30,
    )
    print(result.stdout.strip())
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)

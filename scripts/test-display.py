"""Codex quiet-test wrapper: compile and run display fallback against the shipping dictionary."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ro3-display-tests-') as temp:
    exe = pathlib.Path(temp) / 'test.exe'
    compiler = pathlib.Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
    build = subprocess.run([str(compiler), '/nologo', '/codepage:65001', '/out:' + str(exe),
                            str(root / 'src/RO3.LocalizationTablePatcher/DisplayTextTranslator.cs'),
                            str(root / 'scripts/DisplayTextTranslatorTest.cs')], capture_output=True)
    if build.returncode:
        print('FAILED: display test compilation (scripts/DisplayTextTranslatorTest.cs)')
        raise SystemExit(build.returncode)
    result = subprocess.run([str(exe), str(root / 'Client/BepInEx/config/RO3.LocalizationOverrides.tsv'),
                             str(root / 'Client/BepInEx/config/RO3.LocalizationAliases.tsv')],
                            capture_output=True, timeout=30)
    print('Quiet test run: ' + ('PASSED' if result.returncode == 0 else 'FAILED'))
    print(result.stdout.decode(errors='replace').strip())
    raise SystemExit(result.returncode)

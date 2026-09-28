"""Codex quiet-test wrapper: recruitment history limits and translation cache."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='ro3-chat-tests-') as temp:
    exe = Path(temp) / 'test.exe'
    compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework/v4.0.30319/csc.exe'
    result = subprocess.run([str(compiler), '/nologo', '/codepage:65001', '/out:' + str(exe),
                             str(root / 'src/RO3.LocalizationTablePatcher/ChatTranslationPolicy.cs'),
                             str(root / 'scripts/ChatTranslationPolicyTest.cs')], capture_output=True)
    if result.returncode:
        print('FAILED: chat policy test compilation (scripts/ChatTranslationPolicyTest.cs)')
        raise SystemExit(result.returncode)
    result = subprocess.run([str(exe)], capture_output=True, timeout=30)
    print('Quiet test run: ' + ('PASSED' if result.returncode == 0 else 'FAILED'))
    print(result.stdout.decode(errors='replace').strip())
    raise SystemExit(result.returncode)

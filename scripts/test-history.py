"""Codex quiet-test wrapper for the offline history/dictionary contract check."""
import pathlib
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
start = time.monotonic()
with tempfile.TemporaryDirectory(prefix='ro3-history-') as temp:
    fixture = pathlib.Path(temp) / 'cases.tsv'
    generated = subprocess.run([sys.executable, str(root / 'scripts/build-history-checks.py'), str(fixture)],
                               capture_output=True, timeout=30)
    if generated.returncode or fixture.read_bytes().replace(b'\r\n', b'\n') != (root / 'scripts/history-regression-cases.tsv').read_bytes().replace(b'\r\n', b'\n'):
        print('FAILED: stale history fixture - scripts/history-regression-cases.tsv')
        raise SystemExit(generated.returncode or 1)
result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                         '-File', str(root / 'scripts/inspect-history-rules.ps1'), '-Verify'],
                        capture_output=True, timeout=300)
output = result.stdout.decode(errors='replace')
if result.returncode:
    print('Run the reported case directly with inspect-history-rules.ps1 for details.')
print('Quiet test run: ' + ('PASSED' if result.returncode == 0 else 'FAILED'))
failures_printed = 0
for line in output.splitlines():
    if line.startswith(('Tests:', 'FAILED:')):
        if not line.startswith('FAILED:') or failures_printed < 20:
            print(line)
        if line.startswith('FAILED:'):
            failures_printed += 1
if result.returncode and 'FAILED:' not in output:
    print('FAILED: history harness execution - scripts/inspect-history-rules.ps1')
print(f'Duration: {time.monotonic() - start:.1f}s')
raise SystemExit(result.returncode)

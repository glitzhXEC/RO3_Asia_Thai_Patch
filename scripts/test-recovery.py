"""Codex quiet-test wrapper: recovery and install regression checks in disposable clients."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import sys

repo = pathlib.Path(__file__).resolve().parents[1]
names = ['recovery-compatibility-manifest.json', 'LuaPayload/Localization_en.lua.bytes',
         'LuaPayload/Localization_zh_CN.lua.bytes', 'LuaPayload/Localization_zh_TW.lua.bytes']
failures = []
cases = ['restore', 'repeat', 'missing-backup', 'unknown-manifest', 'missing-state', 'install',
         'after-three', 'after-no-manifest-backup', 'after-zero', 'after-four',
         'after-no-state', 'after-repeat', 'after-install', 'after-cancel',
         'after-patched', 'after-bad-hash', 'after-bad-size', 'after-missing-payload',
         'after-bad-json', 'after-duplicate-module', 'after-missing-module']
if len(sys.argv) > 1:
    cases = [sys.argv[1]]
for case in cases:
    try:
        with tempfile.TemporaryDirectory(prefix='ro3-recovery-') as temp:
            root = pathlib.Path(temp)
            client = root / 'Client (test) & spaces'
            client.mkdir()
            (client / 'ro3.exe').write_bytes(b'placeholder')
            plugin = client / 'BepInEx/plugins/RO3.LocalizationTablePatcher.dll'
            plugin.parent.mkdir(parents=True)
            plugin.write_bytes(b'old')
            state = client / 'BepInEx/config/RO3.RecoveryPatchState.txt'
            state.parent.mkdir()
            state.write_text('PATCHED_MANIFEST_SHA256=' + hashlib.sha256(b'patched').hexdigest())
            recovery = client / 'ro3_Data/StreamingAssets/Recovery'
            for name in names:
                p = recovery / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(b'patched')
                pathlib.Path(str(p) + '.ro3-ja-original').write_bytes(b'original-' + name.encode())
            if case == 'missing-backup':
                pathlib.Path(str(recovery / names[-1]) + '.ro3-ja-original').unlink()
            if case == 'unknown-manifest':
                (recovery / names[0]).write_bytes(b'updated official')
            if case == 'missing-state':
                state.unlink()
            if case.startswith('after-'):
                modules = []
                for name in names[1:]:
                    p = recovery / name
                    p.write_bytes(b'repaired-' + name.encode())
                    modules.append({'payload_relative_path': p.name,
                                    'payload_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
                                    'payload_size': p.stat().st_size})
                if case == 'after-duplicate-module':
                    modules.append(modules[-1])
                if case == 'after-missing-module':
                    modules.pop()
                (recovery / names[0]).write_text(json.dumps({'modules': modules}), encoding='utf-8')
                if case == 'after-no-manifest-backup':
                    pathlib.Path(str(recovery / names[0]) + '.ro3-ja-original').unlink()
                elif case != 'after-four':
                    pathlib.Path(str(recovery / names[-1]) + '.ro3-ja-original').unlink()
                if case == 'after-zero':
                    for name in names[:-1]:
                        pathlib.Path(str(recovery / name) + '.ro3-ja-original').unlink()
                if case == 'after-no-state':
                    state.unlink()
                if case == 'after-patched':
                    state.write_text('PATCHED_MANIFEST_SHA256=' + hashlib.sha256(
                        (recovery / names[0]).read_bytes()).hexdigest())
                if case == 'after-bad-hash':
                    (recovery / names[1]).write_bytes(b'x' * modules[0]['payload_size'])
                if case == 'after-bad-size':
                    modules[0]['payload_size'] += 1
                    (recovery / names[0]).write_text(json.dumps({'modules': modules}))
                if case == 'after-missing-payload':
                    (recovery / names[1]).unlink()
                if case == 'after-bad-json':
                    (recovery / names[0]).write_bytes(b'invalid JSON')
                before = {p.relative_to(client): p.read_bytes()
                          for p in client.rglob('*') if p.is_file() and p != plugin}
            package = root / 'package'
            shutil.copytree(repo / 'packaging', package)
            if case in ('install', 'after-install'):
                payload = package / 'payload'
                (payload / 'BepInEx/plugins').mkdir(parents=True)
                (payload / 'winhttp.dll').write_bytes(b'test')
                (payload / 'BepInEx/plugins/RO3.LocalizationTablePatcher.dll').write_bytes(b'new')
            for _ in range(2 if case in ('repeat', 'after-repeat') else 1):
                result = subprocess.run(['cmd.exe', '/d', '/c', str(package / (
                    'Install-Thai.bat' if case == 'install' else
                    'Recover-After-Official-Repair.bat' if case.startswith('after-') else 'Recover-Thai.bat')),
                    str(client), '--no-pause'], input=b'\n' if case == 'after-cancel' else b'REPAIRED\n',
                    capture_output=True, timeout=30)
                expected_success = case in ('restore', 'repeat', 'install', 'after-three',
                    'after-no-manifest-backup', 'after-zero', 'after-four', 'after-no-state',
                    'after-repeat', 'after-install')
                if len(sys.argv) > 1:
                    print(result.stdout.decode(errors='replace'), result.stderr.decode(errors='replace'))
                assert (result.returncode == 0) == expected_success
            if case.startswith('after-'):
                if case == 'after-cancel':
                    assert plugin.read_bytes() == b'old'
                    assert not list(plugin.parent.glob('*.disabled-*'))
                else:
                    assert not plugin.exists()
                    assert list(plugin.parent.glob('*.disabled-*'))
                archives = list(root.glob('RO3-Recovery-Backup-*'))
                assert len(archives) == (1 if expected_success else 0)
                for relative, content in before.items():
                    metadata = str(relative).endswith('.ro3-ja-original') or relative == state.relative_to(client)
                    target = (archives[0] if metadata and expected_success else client) / relative
                    assert target.read_bytes() == content
                    if metadata and expected_success:
                        assert not (client / relative).exists()
                if expected_success:
                    # The normal recovery entry point must now succeed without
                    # reverting repaired game files or requiring another assertion.
                    result = subprocess.run(['cmd.exe', '/d', '/c', str(package / (
                        'Install-Thai.bat' if case == 'after-install' else 'Recover-Thai.bat')),
                        str(client), '--no-pause'], capture_output=True, timeout=30)
                    assert result.returncode == 0
                    if case == 'after-install':
                        assert plugin.read_bytes() == b'new'
                    for name in names:
                        p = recovery / name
                        assert p.read_bytes() == before[p.relative_to(client)]
                continue
            assert not plugin.exists() or (case == 'install' and plugin.read_bytes() == b'new')
            assert list(plugin.parent.glob('*.disabled-*'))
            for name in names:
                p = recovery / name
                backup = pathlib.Path(str(p) + '.ro3-ja-original')
                if expected_success:
                    assert p.read_bytes() == backup.read_bytes()
                elif not (case == 'unknown-manifest' and name == names[0]):
                    assert p.read_bytes() == b'patched'
                if not (case == 'missing-backup' and name == names[-1]):
                    assert backup.exists()
    except Exception:
        failures.append(case)
print(f'Quiet test run: {len(cases)-len(failures)}/{len(cases)} passed')
for case in failures:
    print(f'FAILED: {case} - scripts/test-recovery.py')
raise SystemExit(bool(failures))

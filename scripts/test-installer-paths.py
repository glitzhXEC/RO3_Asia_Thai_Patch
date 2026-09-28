"""Codex quiet-test wrapper: isolated BAT path regressions, no game execution."""
import pathlib
import shutil
import subprocess
import tempfile


def main():
    packaging = pathlib.Path(__file__).resolve().parents[1] / "packaging"
    failures = []
    total = 0
    with tempfile.TemporaryDirectory(prefix="ro3-path-tests-") as directory:
        root = pathlib.Path(directory)
        package = root / "package"
        package.mkdir()
        for name in ("Install-Thai.bat", "Uninstall-Thai.bat", "Restore-Recovery.ps1"):
            shutil.copyfile(packaging / name, package / name)
        (package / "payload").mkdir()
        (package / "payload" / "winhttp.dll").write_bytes(b"test payload")
        (package / "VERSION.txt").write_text("test\n", encoding="ascii")
        for name in ("ordinary client", "Launcher (2) RO3 Asia Launcher", "RO3 & Client"):
            for use_exe in (False, True, None):
                client = root / (name + (" prompt" if use_exe is None else " exe" if use_exe else " folder"))
                client.mkdir()
                (client / "ro3.exe").write_bytes(b"test placeholder; never executed")
                total += 1
                result = subprocess.run(
                    ["cmd.exe", "/d", "/c", str(package / "Install-Thai.bat"),
                     "" if use_exe is None else str(client / "ro3.exe" if use_exe else client), "--no-pause"],
                    input=(str(client) + "\n").encode("ascii") if use_exe is None else None,
                    capture_output=True, timeout=20,
                )
                marker = client / ".ro3-thai-patch-install.txt"
                if (result.returncode != 0 or not marker.is_file()
                        or b"[OK]" not in result.stdout or result.stderr
                        or not (client / "winhttp.dll").is_file()):
                    failures.append(f"install: {client.name}")
            total += 1
            missing = root / (name + " missing")
            result = subprocess.run(
                ["cmd.exe", "/d", "/c", str(package / "Uninstall-Thai.bat"),
                 str(missing), "--no-pause"], capture_output=True, timeout=20,
            )
            if result.returncode != 1 or b"[ERROR] ro3.exe was not found" not in result.stdout or result.stderr:
                failures.append(f"uninstall rejects missing target: {name}")
    print(f"Quiet test run: {total - len(failures)}/{total} passed")
    for failure in failures:
        print(f"FAILED: {failure}")
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())

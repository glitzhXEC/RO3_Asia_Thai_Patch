#!/usr/bin/env python3
"""Validate strict token order and terminology for reviewed Thai V2 rows."""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT / "_TranslationWorkspace"
SPLIT = WORKSPACE / "split_1000"
MANIFEST = WORKSPACE / "retranslation_v2.json"

PROTECTED_RE = re.compile(
    r"\$\{\d+\}|@\{\d+\}|\^\{\d+\}|(?<![$@^])\{\d+\}|"
    r"%(?:\d+\$)?[sdif]|<[^>]+>|\\n"
)

# V2 uses one canonical mixed Thai/English combat vocabulary.
FORBIDDEN = {
    r"(?<![.A-Z])PATK(?![.A-Z])": "P.ATK",
    r"(?<![.A-Z])MATK(?![.A-Z])": "M.ATK",
    r"(?<![.A-Z])PDEF(?![.A-Z])": "P.DEF",
    r"(?<![.A-Z])MDEF(?![.A-Z])": "M.DEF",
    r"\bST\b": "Single Target",
    r"ระยะประชิดที่เป็นกลาง": "Neutral … ระยะประชิด",
    r"ความเสียหาย(?:ทาง)?กายภาพ": "P.DMG",
    r"ความเสียหาย(?:เวท|เวทย์|เวทมนตร์)": "M.DMG",
    r"คูลดาวน์": "CD",
}


def load_reviewed_indexes() -> set[int]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    indexes = [index for batch in data["batches"].values() for index in batch]
    if len(indexes) != len(set(indexes)):
        raise SystemExit("retranslation_v2.json contains duplicate indexes")
    return set(indexes)


def load_rows() -> dict[int, tuple[str, str, str]]:
    rows: dict[int, tuple[str, str, str]] = {}
    for path in sorted(SPLIT.glob("part_*.tsv")):
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for line, row in enumerate(csv.DictReader(handle, delimiter="\t"), start=2):
                index = int(row["Index"])
                rows[index] = (
                    row["English"],
                    row["Thai_Translation"],
                    f"{path.name}:{line}",
                )
    return rows


def main() -> int:
    reviewed = load_reviewed_indexes()
    rows = load_rows()
    failures: list[str] = []
    for index in sorted(reviewed):
        if index not in rows:
            failures.append(f"{index}: missing workspace row")
            continue
        source, target, context = rows[index]
        if source == target or not re.search(r"[\u0E00-\u0E7F]", target):
            failures.append(f"{context}: V2 target is not translated")
        if PROTECTED_RE.findall(source) != PROTECTED_RE.findall(target):
            failures.append(f"{context}: protected token order differs from source")
        for pattern, preferred in FORBIDDEN.items():
            if re.search(pattern, target, flags=re.IGNORECASE):
                failures.append(
                    f"{context}: non-V2 terminology; use {preferred!r}: {target!r}"
                )
    if failures:
        raise SystemExit("Thai V2 terminology validation failed:\n" + "\n".join(failures))
    print(f"Thai V2 terminology OK: reviewed={len(reviewed)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
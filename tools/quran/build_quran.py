#!/usr/bin/env python3
"""Build apps/mobile/assets/quran/quran.json — the bundled, offline mushaf data (spec §6.6, §10).

    python3 tools/quran/build_quran.py

Sources (pinned by version + npm sha512 integrity; never edited by hand):
  * Text  — npm `quran-json` 3.1.2 (CC BY 4.0): Uthmani Hafs text from The Noble Qur'an Encyclopedia
            (QuranEnc / KFGQPC edition), republished verbatim with credit.
  * Layout — npm `quran-meta` 7.0.0 (MIT): Madani 604-page, juz, hizb-quarter and sajda boundaries
            (Tanzil metadata).

The licence of the text source is an open product decision (APP_SPEC §13.1): swap SOURCES below for
the licensed source (e.g. Tanzil `quran-uthmani.xml`) before release and re-run. The script refuses to
write unless every structural check passes, and prints the asset's sha256 for the checksum test.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from npm_fetch import fetch  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/mobile/assets/quran/quran.json"

SOURCES = {
    "text": {
        "name": "quran-json",
        "version": "3.1.2",
        "url": "https://registry.npmjs.org/quran-json/-/quran-json-3.1.2.tgz",
        "integrity": "sha512-K0RURQSueVUMpDkZCnfXhck6YCX2lEJCar0SsI2naNDgei/crtrVfRHavZk14tw0TJlGQd/zl3tABSOGQrJLYQ==",
        "licence": "CC BY 4.0 — text: The Noble Qur'an Encyclopedia (quranenc.com), verbatim",
    },
    "meta": {
        "name": "quran-meta",
        "version": "7.0.0",
        "url": "https://registry.npmjs.org/quran-meta/-/quran-meta-7.0.0.tgz",
        "integrity": "sha512-nxC+DBRb3ibTUyNVxWz6O7oS6/2ZYGaKlSG4XR43U9FdsVvgg1CVdlQFwy7/orUaLJ5sfDx2gBmTS/ixi8M7xQ==",
        "licence": "MIT — Madani page/juz/hizb metadata (Tanzil)",
    },
}

EXPECTED = {"surahs": 114, "ayat": 6236, "pages": 604, "juz": 30, "quarters": 240, "sajdas": 15}


def js_list(src: str, key: str) -> list:
    """Extract `key: [ ... ]` from the quran-meta bundle as a Python list (it is JSON-compatible)."""
    m = re.search(key + r":\s*(\[.*?\n\t\])", src, re.S)
    if not m:
        raise SystemExit(f"{key} not found in quran-meta")
    body = re.sub(r",(\s*[\]\}])", r"\1", m.group(1).replace("\t", ""))
    return json.loads(body.replace("false", "false").replace("true", "true"))


def main() -> None:
    text_files = fetch(SOURCES["text"]["url"], SOURCES["text"]["integrity"])
    meta_files = fetch(SOURCES["meta"]["url"], SOURCES["meta"]["integrity"])

    chapters = json.loads(text_files["package/dist/quran.json"])
    hafs = next(v.decode() for k, v in meta_files.items() if re.search(r"HafsLists-[^/]+\.js$", k))

    # Index 0 and any trailing row past the last ayah are sentinels.
    surah_list = [row for row in js_list(hafs, "SurahList")[1:] if row[0] <= 6236 and row[1] > 0 and row[4]]
    page_list = js_list(hafs, "PageList")[1:]
    juz_list = js_list(hafs, "JuzList")[1:]
    quarter_list = js_list(hafs, "HizbQuarterList")[1:]
    sajda_list = js_list(hafs, "SajdaList")
    for lst in (page_list, juz_list, quarter_list):
        if lst and lst[-1] == 6237:  # trailing sentinel
            lst.pop()

    # absolute ayah id (1-based) -> (surah, ayah)
    index: list[tuple[int, int]] = []
    for s, row in enumerate(surah_list, start=1):
        index.extend((s, a) for a in range(1, row[1] + 1))
    at = lambda abs_id: list(index[abs_id - 1])  # noqa: E731

    errors = []
    if len(chapters) != EXPECTED["surahs"]:
        errors.append(f"{len(chapters)} surahs")
    total = sum(len(c["verses"]) for c in chapters)
    if total != EXPECTED["ayat"] or len(index) != EXPECTED["ayat"]:
        errors.append(f"{total} / {len(index)} ayat")
    for c, row in zip(chapters, surah_list):
        if len(c["verses"]) != row[1] or c["total_verses"] != row[1]:
            errors.append(f"surah {c['id']}: text has {len(c['verses'])} ayat, metadata {row[1]}")
        if [v["id"] for v in c["verses"]] != list(range(1, row[1] + 1)):
            errors.append(f"surah {c['id']}: ayah numbers are not sequential")
        if any(not v["text"].strip() for v in c["verses"]):
            errors.append(f"surah {c['id']}: empty ayah")
    for key, lst in (("pages", page_list), ("juz", juz_list), ("quarters", quarter_list), ("sajdas", sajda_list)):
        if len(lst) != EXPECTED[key]:
            errors.append(f"{len(lst)} {key}")
        if lst != sorted(lst):
            errors.append(f"{key} not ascending")
    if errors:
        raise SystemExit("refusing to write quran.json:\n  " + "\n  ".join(errors))

    # Start page of each surah = last page whose first ayah is <= the surah's first ayah.
    def page_of(abs_id: int) -> int:
        lo, hi = 0, len(page_list) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if page_list[mid] <= abs_id:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    data = {
        "format": 1,
        "riwaya": "hafs",
        "script": "uthmani",
        "sources": {k: {x: v[x] for x in ("name", "version", "licence")} for k, v in SOURCES.items()},
        # [nameAr, nameTransliterated, "m"|"d", ayahCount, startPage]
        "surahs": [
            [c["name"], c["transliteration"], "m" if row[5] else "d", row[1], page_of(row[0])]
            for c, row in zip(chapters, surah_list)
        ],
        "pages": [at(x) for x in page_list],
        "juz": [at(x) for x in juz_list],
        "quarters": [at(x) for x in quarter_list],
        "sajdas": [at(x) for x in sajda_list],
        "ayat": [[v["text"] for v in c["verses"]] for c in chapters],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    blob = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode()
    OUT.write_bytes(blob)
    print(f"wrote {OUT.relative_to(ROOT)}  {len(blob):,} bytes  sha256={hashlib.sha256(blob).hexdigest()}")
    print(f"  {EXPECTED['surahs']} surahs · {EXPECTED['ayat']} ayat · {EXPECTED['pages']} pages · 30 juz · 240 quarters · 15 sajdas")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build apps/mobile/assets/quran/layout_v2.json — the line-by-line layout of the printed Madani mushaf
(King Fahd Complex, 15 lines, 604 pages) with the QCF V2 glyph code of every word (spec §5.11, §10).

    python3 tools/quran/build_layout.py            # fetches the 604 pages once (cached), validates, writes
    python3 tools/quran/build_layout.py --check    # rebuild in memory and fail if the asset differs

Source: Quran.com API v4 (Quran Foundation), public, no key needed:
  GET https://api.quran.com/api/v4/verses/by_page/{page}?words=true&per_page=50
      &word_fields=code_v2,line_number,page_number,char_type_name
The glyph codes index the per-page KFGQPC «QCF V2» fonts (`p{page}.ttf`), which the app downloads per
page on demand from `Env.mushafFontBaseUrl` (default https://static.qurancdn.com/fonts/quran/hafs/v2/ttf/).
Fonts © King Fahd Glorious Qur'an Printing Complex (KFGQPC), used under its terms (owner accepted, §10).

Asset format (compact, ~1.6 MB):
  {"format":1, "source":{…}, "starts":[[s,a] × 604], "pages":[ page1, …, page604 ]}
  starts = the first ayah of every printed page (this print; 25 differ from the Tanzil metadata)
  page  = [line1, …, line15]               exactly 15 entries (the printed line slots)
  line  = {"s": n}                          surah-name band for surah n
        | {"b": 1}                          the Basmala line
        | {"c": 1, "w": [...]} / {"w": [...]}  verse words, "c" → centred (pages 1–2)
  word  = [code, surah, ayah, position, kind]  kind 0 word · 1 ayah-end marker · 2 other (pause, sajdah…)
Pages 1–2 have fewer printed lines; their missing slots are empty ({"e":1}) so the text sits centred.

The script refuses to write unless: 604 pages × 15 slots, every ayah (6236) present exactly once in
reading order with its end marker, no ayah split across pages, and only the known source correction
applied (EXPECTED_FIXES: the end marker of 84:21 is tagged one line too early). Responses are cached in
tools/quran/.cache/ (git-ignored); delete it to refetch.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "apps/mobile/assets/quran/layout_v2.json"
QURAN = ROOT / "apps/mobile/assets/quran/quran.json"
CACHE = ROOT / "tools/quran/.cache/qurancom_v4"
API = "https://api.quran.com/api/v4/verses/by_page/{page}?words=true&per_page=50&page={n}&word_fields=code_v2,line_number,page_number,char_type_name"
SOURCE = {
    "layout": "Quran.com API v4 /verses/by_page (Quran Foundation) — line_number + code_v2 per word",
    "fonts": "KFGQPC QCF V2 per-page fonts p{page}.ttf (King Fahd Glorious Qur'an Printing Complex)",
    "font_url": "https://static.qurancdn.com/fonts/quran/hafs/v2/ttf/p{page}.ttf",
    "licence": "Glyph fonts © KFGQPC, used under its terms; layout data from Quran.com — attribution required (APP_SPEC §10)",
    "built": "",
}
KIND = {"word": 0, "end": 1}
FIXES: list[str] = []
# Expected source corrections; anything else stops the build for a look.
EXPECTED_FIXES = {"84:21 word 7: line 13 → 14"}


def fetch_page(page: int) -> list[dict]:
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / f"{page:03}.json"
    if f.exists():
        return json.loads(f.read_text("utf-8"))
    verses: list[dict] = []
    n = 1
    while True:
        url = API.format(page=page, n=n)
        for attempt in range(5):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": "yaqeen-build-layout/1"})
                with urllib.request.urlopen(req, timeout=60) as r:
                    d = json.loads(r.read())
                break
            except Exception as e:  # noqa: BLE001 — retry transient network errors
                if attempt == 4:
                    raise SystemExit(f"page {page}: {e}")
                time.sleep(2 * (attempt + 1))
        verses += d["verses"]
        nxt = d["pagination"]["next_page"]
        if not nxt:
            break
        n = nxt
    f.write_text(json.dumps(verses, ensure_ascii=False), "utf-8")
    return verses


def build() -> tuple[dict, dict]:
    quran = json.loads(QURAN.read_text("utf-8"))
    ayah_counts = [s[3] for s in quran["surahs"]]
    page_starts = [tuple(r) for r in quran["pages"]]
    pages = []
    seen: list[tuple[int, int]] = []
    kinds: dict[str, int] = {}
    # The endpoint picks verses by one page index but its page_number/line_number fields follow the
    # V2 print (e.g. /by_page/121 returns 5:77 whose words sit on page 120): collect every verse once
    # and place each word by its own page_number/line_number.
    by_key: dict[tuple[int, int], dict] = {}
    for page in range(1, 605):
        for v in fetch_page(page):
            key = tuple(int(x) for x in v["verse_key"].split(":"))
            by_key.setdefault(key, v)
    on_page: dict[int, list[dict]] = {}
    for key in sorted(by_key):
        v = by_key[key]
        wp = {w["page_number"] for w in v["words"]}
        if len(wp) != 1:
            raise SystemExit(f"{v['verse_key']} spans pages {sorted(wp)}")
        on_page.setdefault(wp.pop(), []).append(v)
    starts = []
    for page in range(1, 605):
        verses = on_page.get(page)
        if not verses:
            raise SystemExit(f"page {page}: no verses")
        starts.append([int(x) for x in verses[0]["verse_key"].split(":")])
        lines: dict[int, list] = {}
        first_line_of_surah: dict[int, int] = {}
        for v in verses:
            s, a = (int(x) for x in v["verse_key"].split(":"))
            seen.append((s, a))
            ends = 0
            prev_line = 0
            for w in sorted(v["words"], key=lambda x: x["position"]):
                t = w["char_type_name"]
                kinds[t] = kinds.get(t, 0) + 1
                k = KIND.get(t, 2)
                ends += k == 1
                ln = int(w["line_number"])
                if not 1 <= ln <= 15:
                    raise SystemExit(f"{s}:{a} line {ln}")
                if ln < prev_line:
                    # Words of an ayah never go back a line. Known source glitch: the end marker of
                    # 84:21 (page 589) is tagged line 13 while its last words are on line 14.
                    FIXES.append(f"{s}:{a} word {w['position']}: line {ln} → {prev_line}")
                    ln = prev_line
                prev_line = ln
                lines.setdefault(ln, []).append([w["code_v2"], s, a, int(w["position"]), k])
                if a == 1:
                    first_line_of_surah.setdefault(s, ln)
            if ends != 1:
                raise SystemExit(f"{s}:{a}: {ends} end markers")
        slots: list[dict | None] = [None] * 15
        for ln, words in lines.items():
            slots[ln - 1] = {"w": words}
        # Reserved slots before a surah's first line: the Basmala (not for 1 and 9), then the name band.
        # In this print a band can sit on the previous page's last line (An-Nisa's name ends page 76).
        for s, ln in first_line_of_surah.items():
            need = ([{"b": 1}] if s not in (1, 9) else []) + [{"s": s}]
            i = ln - 2
            for item in need:
                target, j = (slots, i) if i >= 0 else ((pages[-1] if pages else None), 15 + i)
                if target is None or not 0 <= j < 15 or target[j] is not None:
                    raise SystemExit(f"page {page}: no free line for {item} of surah {s}")
                target[j] = item
                i -= 1
        if page <= 2:
            # Al-Fatihah and the opening of Al-Baqarah: a short, centred page.
            for sl in slots:
                if sl and "w" in sl:
                    sl["c"] = 1
        pages.append(slots)
    for page, slots in enumerate(pages, start=1):
        for i, sl in enumerate(slots):
            if sl is None:
                if page <= 2:
                    slots[i] = {"e": 1}
                else:
                    raise SystemExit(f"page {page}: line {i + 1} is empty")
    expected = [(s + 1, a + 1) for s, n in enumerate(ayah_counts) for a in range(n)]
    if seen != expected:
        raise SystemExit(f"ayat out of order or missing: {len(seen)} seen, {len(expected)} expected")
    if set(FIXES) != EXPECTED_FIXES:
        raise SystemExit(f"unexpected line corrections: {sorted(set(FIXES) ^ EXPECTED_FIXES)}")
    diffs = [(i + 1, tuple(s), page_starts[i]) for i, s in enumerate(starts) if tuple(s) != page_starts[i]]
    if diffs:
        print(f"note: {len(diffs)} page starts differ from quran.json (Tanzil): {diffs[:12]}")
    return {"format": 1, "source": SOURCE, "starts": starts, "pages": pages}, kinds


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    data, kinds = build()
    if args.check:
        old = json.loads(OUT.read_text("utf-8"))
        if old["pages"] != data["pages"]:
            raise SystemExit("layout_v2.json is out of date — run tools/quran/build_layout.py")
        print("layout_v2.json is current")
        return
    data["source"]["built"] = time.strftime("%Y-%m-%d")
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), "utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} — {OUT.stat().st_size:,} bytes; char types {kinds}")


if __name__ == "__main__":
    main()

"""Builds the tafsir pack (spec §6.6, §10) from QuranEnc.com — unaltered text, verified complete.

  python3 -I tools/tafsir/build_pack.py                      # fetch from the QuranEnc API
  python3 -I tools/tafsir/build_pack.py --from export.json    # or a QuranEnc export saved locally
  python3 -I tools/tafsir/build_pack.py --key arabic_moyassar --out build/packs
  Or on GitHub: Actions › Tafsir pack › Run workflow — builds, then uploads to Cloudflare R2 (docs/CONTENT_PACKS.md).

QuranEnc republishing terms (honoured by the app): no modification, addition or deletion · credit
QuranEnc.com as publisher and source · state the version · keep the transcript information · report
notes to the source · follow the latest version (the app's weekly pack check) · no inappropriate ads.

Output: <out>/tafsir-<key>.json = {"<surah>:<ayah>": "<text>"} and tafsir-<key>.meta.json with the
source, version and sha256 to register as a `content_packs` row (see services/api/src/db/seed.ts).
The text is never committed to git; host the file and point TAFSIR_PACK_URL at it.
"""
import argparse
import hashlib
import json
import pathlib
import sys
import urllib.request

API = 'https://quranenc.com/api/v1'
TOTAL_AYAT = 6236


def get(url: str):
    with urllib.request.urlopen(urllib.request.Request(url, headers={'Accept': 'application/json'}), timeout=60) as r:
        return json.load(r)


def find_translation(key: str | None):
    """The QuranEnc entry for the Arabic Muyassar (or the requested key), with its version."""
    listing = get(f'{API}/translations/list/ar')
    items = listing.get('translations', listing) if isinstance(listing, dict) else listing
    for t in items:
        k = t.get('key', '')
        title = f"{t.get('title', '')} {t.get('description', '')}"
        if (key and k == key) or (not key and t.get('language_iso_code') == 'ar' and ('ميسر' in title or 'moyassar' in k or 'muyassar' in k)):
            return t
    sys.exit(f'translation not found (key={key}); available ar keys: {[t.get("key") for t in items if t.get("language_iso_code") == "ar"]}')


def rows_from_api(key: str):
    for sura in range(1, 115):
        data = get(f'{API}/translation/sura/{key}/{sura}')
        for r in data['result']:
            yield int(r['sura']), int(r['aya']), r['translation']


def rows_from_file(path: pathlib.Path):
    data = json.loads(path.read_text(encoding='utf-8'))
    for r in data.get('result', data) if isinstance(data, dict) else data:
        yield int(r['sura']), int(r['aya']), r['translation']


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--key', help='QuranEnc translation key (default: discover the Arabic Muyassar)')
    ap.add_argument('--from', dest='src', type=pathlib.Path, help='local QuranEnc export instead of the API')
    ap.add_argument('--version', help='source version when using --from')
    ap.add_argument('--out', type=pathlib.Path, default=pathlib.Path('build/packs'))
    a = ap.parse_args()

    root = pathlib.Path(__file__).resolve().parents[2]
    quran = json.loads((root / 'apps/mobile/assets/quran/quran.json').read_text(encoding='utf-8'))
    # surahs: [nameAr, nameEn, type, ayahCount, startPage]
    counts = [s[3] for s in quran['surahs']]

    if a.src:
        meta = {'key': a.key or a.src.stem, 'version': a.version or 'unknown', 'title': 'التفسير الميسر'}
        rows = rows_from_file(a.src)
    else:
        t = find_translation(a.key)
        meta = {'key': t['key'], 'version': t.get('version'), 'title': t.get('title'), 'last_update': t.get('last_update')}
        rows = rows_from_api(t['key'])

    pack: dict[str, str] = {}
    for sura, aya, text in rows:
        text = (text or '').strip()
        if not text:
            sys.exit(f'empty text at {sura}:{aya} — refusing to build an incomplete pack')
        pack[f'{sura}:{aya}'] = text  # unaltered (terms: no modification)
    if len(pack) != TOTAL_AYAT:
        sys.exit(f'expected {TOTAL_AYAT} ayat, got {len(pack)}')
    # Same verse map as the bundled mushaf, so every ayah the reader shows has its tafsir.
    for s, n in enumerate(counts, start=1):
        for ayah in range(1, n + 1):
            if f'{s}:{ayah}' not in pack:
                sys.exit(f'missing {s}:{ayah}')

    a.out.mkdir(parents=True, exist_ok=True)
    body = json.dumps(pack, ensure_ascii=False, separators=(',', ':'), sort_keys=False).encode('utf-8')
    name = f"tafsir-{meta['key']}"
    (a.out / f'{name}.json').write_bytes(body)
    meta.update({
        'source': 'QuranEnc.com',
        'publisher': 'مجمع الملك فهد لطباعة المصحف الشريف',
        'sha256': hashlib.sha256(body).hexdigest(),
        'sizeBytes': len(body),
        'ayat': len(pack),
    })
    (a.out / f'{name}.meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()

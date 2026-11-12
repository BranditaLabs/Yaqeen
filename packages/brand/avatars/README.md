# Yaqeen profile avatars — «صور يقين الرمزية»

16 faceless avatars (8 men, 8 women) in the brand palette. Faceless by design: identity comes from the
head covering (kufi, ghutra & agal, imama · hijab, khimar, niqab, shayla), the beard, the garment, skin
tone and colour — no eyes, nose or mouth.

```bash
CHROMIUM_PATH=/path/to/chromium python3 packages/brand/avatars/generate_avatars.py
```

- `svg/<id>.svg` — 512 × 512 vector masters (edit `generate_avatars.py`, never the SVGs by hand)
- `apps/mobile/assets/avatars/<id>.webp` — what the app ships (512 px, ~12 KB each, transparent corners)
- `avatars.json` — catalogue: `id`, `gender` (`m`/`f`), Arabic and English labels

Requires Python with Pillow, Node with Playwright + Chromium.

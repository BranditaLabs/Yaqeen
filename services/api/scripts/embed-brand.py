#!/usr/bin/env python3
"""Embed downscaled brand artwork into services/api/src/web/brand-assets.ts (public profile page).

Run from the repo root:  python3 services/api/scripts/embed-brand.py
"""
import base64
import io
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[3]
BRAND = ROOT / "packages/brand"
OUT = ROOT / "services/api/src/web/brand-assets.ts"

SOURCES = {
    "lockupNavyAr": ("logo/lockup-ar-horizontal-navy.png", 300),
    "lockupWhiteAr": ("logo/lockup-ar-horizontal-white.png", 300),
    "lockupNavyEn": ("logo/lockup-en-horizontal-navy.png", 300),
    "lockupWhiteEn": ("logo/lockup-en-horizontal-white.png", 300),
    "icon": ("web/icon-512.png", 256),
}


def encode(path: pathlib.Path, width: int) -> str:
    im = Image.open(path).convert("RGBA")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode()


lines = [
    "/**",
    " * Brand artwork for the public profile page, embedded so the API image needs no asset files.",
    " * Generated from packages/brand by services/api/scripts/embed-brand.py — do not edit by hand;",
    " * the logo always comes from artwork, never typeset (CLAUDE.md rule 8).",
    " */",
    "export const BRAND_PNG = {",
]
for key, (rel, width) in SOURCES.items():
    lines.append(f"  {key}: '{encode(BRAND / rel, width)}',")
lines += ["} as const;", "", "export type BrandAsset = keyof typeof BRAND_PNG;", ""]
OUT.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")

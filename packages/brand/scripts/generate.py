"""
Regenerates every derived brand asset from packages/brand/source (designer originals).

    python3 packages/brand/scripts/generate.py      (needs Pillow)

Outputs: logo/ (trimmed, ≤1600px), app-icon/ios, app-icon/android, web/, splash/,
then copies what each app needs into apps/mobile/assets/brand and apps/admin/public.
"""
import json, shutil
from pathlib import Path
from PIL import Image, ImageDraw

BRAND = Path(__file__).resolve().parents[1]
REPO = BRAND.parents[1]
SRC = BRAND / 'source'
tokens = json.loads((REPO / 'packages/design-tokens/tokens.json').read_text())
STOPS = [(tuple(int(c[i:i + 2], 16) for i in (1, 3, 5)), p) for c, p in tokens['gradient']['brand']['stops']]


def gradient(w, h):
    row = Image.new('RGB', (w, 1))
    px = row.load()
    for x in range(w):
        t = x / (w - 1)
        for (c0, p0), (c1, p1) in zip(STOPS, STOPS[1:]):
            if p0 <= t <= p1:
                u = (t - p0) / (p1 - p0) if p1 > p0 else 0
                px[x, 0] = tuple(round(c0[i] + (c1[i] - c0[i]) * u) for i in range(3))
                break
    return row.resize((w, h))


def trim(im, pad_frac=0.04):
    im = im.crop(im.getchannel('A').getbbox())
    pad = int(max(im.size) * pad_frac)
    out = Image.new('RGBA', (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
    out.paste(im, (pad, pad))
    return out


def place(canvas, mark, frac, dy=0.02):
    w = int(canvas.width * frac)
    m = mark.resize((w, int(mark.height * w / mark.width)), Image.LANCZOS)
    canvas.paste(m, ((canvas.width - m.width) // 2, (canvas.height - m.height) // 2 + int(dy * canvas.height)), m)
    return canvas


def out(rel):
    p = BRAND / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    return p


# 1) logos
for f in sorted(SRC.glob('*.png')):
    im = Image.open(f).convert('RGBA')
    if f.name.startswith('tile-'):
        im = im.convert('RGB')
    else:
        im = trim(im)
    im.thumbnail((1600, 1600), Image.LANCZOS)
    im.save(out(f'logo/{f.name}'), optimize=True)

white = Image.open(SRC / 'mark-white.png').convert('RGBA')
white = white.crop(white.getchannel('A').getbbox())

# 2) iOS (opaque 1024 + iOS 18 dark/tinted variants)
place(gradient(1024, 1024).convert('RGBA'), white, 0.66).convert('RGB').save(out('app-icon/ios/AppIcon-1024.png'))
place(Image.new('RGBA', (1024, 1024), (0, 0, 0, 0)), white, 0.66).save(out('app-icon/ios/AppIcon-1024-dark.png'))
place(Image.new('RGBA', (1024, 1024), (0, 0, 0, 255)), white.convert('LA').convert('RGBA'), 0.66).convert('RGB').save(
    out('app-icon/ios/AppIcon-1024-tinted.png'))

# 3) Android adaptive (432px = 108dp@4x; keep the mark inside the 66dp safe zone)
gradient(432, 432).save(out('app-icon/android/ic_launcher_background.png'))
place(Image.new('RGBA', (432, 432), (0, 0, 0, 0)), white, 0.52).save(out('app-icon/android/ic_launcher_foreground.png'))
mono = Image.new('RGBA', white.size, (255, 255, 255, 0))
mono.putalpha(white.getchannel('A'))
place(Image.new('RGBA', (432, 432), (0, 0, 0, 0)), mono, 0.52).save(out('app-icon/android/ic_launcher_monochrome.png'))
place(gradient(512, 512).convert('RGBA'), white, 0.62).convert('RGB').save(out('app-icon/android/play-store-512.png'))
navy = Image.open(SRC / 'mark-navy.png').convert('RGBA')
navy = navy.crop(navy.getchannel('A').getbbox())
# Light splash (porcelain): navy mark. Android 12 shows it inside a 192px circle.
place(Image.new('RGBA', (288, 288), (0, 0, 0, 0)), navy, 0.55).save(out('splash/android12-splash-icon.png'))


# 4) web
def rounded(size):
    t = place(gradient(size, size).convert('RGBA'), white, 0.64)
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.22), fill=255)
    t.putalpha(m)
    return t


rounded(512).save(out('web/icon-512.png'))
rounded(192).save(out('web/icon-192.png'))
place(gradient(180, 180).convert('RGBA'), white, 0.64).convert('RGB').save(out('web/apple-touch-icon.png'))
rounded(256).save(out('web/favicon.ico'), sizes=[(16, 16), (32, 32), (48, 48)])

# 5) splash — light, mark only. The mark is split by colour into the navy wings and the gold
#    diamond on identical canvases, so the in-app splash can animate them and they recombine exactly.
NAVY, GOLD = (0x0A, 0x15, 0x30), (0xC6, 0xA8, 0x67)
mk = Image.open(SRC / 'mark-navy.png').convert('RGBA')
mk = mk.crop(mk.getchannel('A').getbbox())
pad = int(mk.width * 0.06)
full = Image.new('RGBA', (mk.width + 2 * pad, mk.height + 2 * pad), (0, 0, 0, 0))
full.paste(mk, (pad, pad))
wings = Image.new('RGBA', full.size, (0, 0, 0, 0))
dia = Image.new('RGBA', full.size, (0, 0, 0, 0))
fp, wp, dp = full.load(), wings.load(), dia.load()
for y in range(full.height):
    for x in range(full.width):
        r, g, b, a = fp[x, y]
        if a == 0:
            continue
        dn = sum((v - c) ** 2 for v, c in zip((r, g, b), NAVY))
        dg = sum((v - c) ** 2 for v, c in zip((r, g, b), GOLD))
        if dg < dn:
            dp[x, y] = (*GOLD, a)
        else:
            wp[x, y] = (*NAVY, a)
for name, im in (('splash-mark-full', full), ('splash-wings-navy', wings), ('splash-diamond-gold', dia)):
    im.resize((720, round(im.height * 720 / im.width)), Image.LANCZOS).save(out(f'logo/{name}.png'), optimize=True)
lock = Image.open(BRAND / 'logo/splash-mark-full.png').convert('RGBA')
s = Image.new('RGBA', (1242, 2688), (0xF7, 0xF9, 0xFC, 255))
w = int(1242 * 0.35)
lk = lock.resize((w, int(lock.height * w / lock.width)), Image.LANCZOS)
s.paste(lk, ((1242 - w) // 2, int(2688 * 0.46) - lk.height // 2), lk)
s.convert('RGB').save(out('splash/splash-preview-1242x2688.png'))


# 6) copy into apps
mob = REPO / 'apps/mobile/assets/brand'
mob.mkdir(parents=True, exist_ok=True)
for name in ['mark-navy', 'mark-white', 'splash-wings-navy', 'splash-diamond-gold', 'splash-mark-full', 'lockup-stacked-white', 'lockup-stacked-navy', 'lockup-horizontal-navy',
             'lockup-ar-horizontal-navy', 'lockup-ar-horizontal-white']:
    src = BRAND / f'logo/{name}.png'
    im = Image.open(src)
    im.thumbnail((900, 900), Image.LANCZOS)  # 3x of the largest on-screen size
    im.save(mob / f'{name}.png', optimize=True)
launch = mob / 'launcher'
launch.mkdir(exist_ok=True)
for f in [*(BRAND / 'app-icon/ios').glob('*.png'), *(BRAND / 'app-icon/android').glob('*.png'), BRAND / 'splash/android12-splash-icon.png']:
    shutil.copy(f, launch / f.name)
pub = REPO / 'apps/admin/public'
(pub / 'brand').mkdir(parents=True, exist_ok=True)
for name in ['lockup-stacked-navy', 'lockup-horizontal-navy', 'mark-navy', 'mark-white']:
    im = Image.open(BRAND / f'logo/{name}.png')
    im.thumbnail((600, 600), Image.LANCZOS)
    im.save(pub / f'brand/{name}.png', optimize=True)
for f in ['favicon.ico', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png']:
    shutil.copy(BRAND / f'web/{f}', pub / f)
print('brand assets generated')

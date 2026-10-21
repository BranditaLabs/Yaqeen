"""Installs the generated brand artwork into the Flutter native projects (apps/mobile/{android,ios}).

Run after scripts/generate.py:  python3 -I packages/brand/scripts/install_native.py
Logo artwork only (brand rule 8): nothing here typesets «يقين».
"""
import json
import pathlib
import shutil

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[3]
BRAND = ROOT / 'packages/brand'
APP = ROOT / 'apps/mobile'
RES = APP / 'android/app/src/main/res'
XC = APP / 'ios/Runner/Assets.xcassets'
PORCELAIN = '#F7F9FC'

DPI = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def resized(src: pathlib.Path, px: int) -> Image.Image:
    return Image.open(src).convert('RGBA').resize((px, px), Image.LANCZOS)


def android() -> None:
    bg = BRAND / 'app-icon/android/ic_launcher_background.png'
    fg = BRAND / 'app-icon/android/ic_launcher_foreground.png'
    mono = BRAND / 'app-icon/android/ic_launcher_monochrome.png'
    for name, scale in DPI.items():
        # Legacy square icon: background + foreground, 48 dp.
        size = round(48 * scale)
        legacy = resized(bg, size)
        legacy.alpha_composite(resized(fg, size))
        (RES / f'mipmap-{name}').mkdir(parents=True, exist_ok=True)
        legacy.convert('RGB').save(RES / f'mipmap-{name}/ic_launcher.png')
        # Adaptive layers: 108 dp.
        layer = round(108 * scale)
        d = RES / f'drawable-{name}'
        d.mkdir(parents=True, exist_ok=True)
        resized(bg, layer).convert('RGB').save(d / 'ic_launcher_background.png')
        resized(fg, layer).save(d / 'ic_launcher_foreground.png')
        resized(mono, layer).save(d / 'ic_launcher_monochrome.png')
        # Launch mark (pre-Android-12 window background): 120 dp.
        resized(BRAND / 'splash/android12-splash-icon.png', round(120 * scale)).save(d / 'splash_mark.png')
    (RES / 'mipmap-anydpi-v26').mkdir(parents=True, exist_ok=True)
    (RES / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n'
    )
    # Android 12+ splash API icon: 288 px canvas = 192 dp safe area at xxxhdpi.
    shutil.copy(BRAND / 'splash/android12-splash-icon.png', RES / 'drawable-xxxhdpi/splash_icon.png')


def ios() -> None:
    icons = XC / 'AppIcon.appiconset'
    for f in icons.glob('*.png'):
        f.unlink()
    for variant, name in [('', 'AppIcon-1024.png'), ('dark', 'AppIcon-1024-dark.png'), ('tinted', 'AppIcon-1024-tinted.png')]:
        shutil.copy(BRAND / 'app-icon/ios' / name, icons / name)
    images = [{'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': 'AppIcon-1024.png'}]
    for appearance, name in [('dark', 'AppIcon-1024-dark.png'), ('tinted', 'AppIcon-1024-tinted.png')]:
        images.append({
            'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': name,
            'appearances': [{'appearance': 'luminosity', 'value': appearance}],
        })
    (icons / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

    launch = XC / 'LaunchImage.imageset'
    mark = BRAND / 'logo/splash-mark-full.png'
    base = Image.open(mark).convert('RGBA')
    for scale, suffix in [(1, ''), (2, '@2x'), (3, '@3x')]:
        w = 136 * scale  # the Flutter splash draws the mark 136 pt wide — no jump at hand-off
        h = round(base.height * w / base.width)
        base.resize((w, h), Image.LANCZOS).save(launch / f'LaunchImage{suffix}.png')


if __name__ == '__main__':
    android()
    ios()
    print('native icons and launch artwork installed')

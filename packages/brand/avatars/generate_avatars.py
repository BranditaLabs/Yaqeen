#!/usr/bin/env python3
"""
Yaqeen profile avatars — «صور يقين الرمزية».

Faceless by design (the convention of premium Islamic apps): no eyes, nose or mouth are drawn.
Identity comes from the head covering, the beard, the garment, the skin tone and the colour.
Brand palette only (packages/design-tokens/tokens.json), soft light from the top-left, no
ornament.

  python3 packages/brand/avatars/generate_avatars.py
  → packages/brand/avatars/svg/<id>.svg            (512 × 512 masters)
  → apps/mobile/assets/avatars/<id>.webp           (512 px, what the app ships; rendered with
                                                     headless Chromium via render_png.js, then WebP)
  → packages/brand/avatars/avatars.json            (catalogue: id, gender, label ar/en)
"""
from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]

# ----------------------------------------------------------------------------- palette (tokens)

C = dict(
    midnight="#0A1530", navy="#10214D", lapis="#1F3F94", royal="#2A52B8", sky="#8FB0E0",
    sky200="#C7D8F0", sky100="#E3EBF7", ice="#E9EFF9", mist="#C8D5EC", porcelain="#F3F6FB",
    gold="#C6A867", goldDeep="#4A3C17", goldLight="#E9D49E", gold100="#F1E9D9", gold200="#E3D4B3",
    cream="#FFFBF1", sand="#F4E8C8", white="#FFFFFF", slate700="#475064", slate400="#858A98",
    slate200="#C2C5CB", navy600="#4C597A", navy400="#8890A6", lapis500="#576FAF", lapis300="#8F9FCA",
)

SKIN = {  # base, shadow
    "s1": ("#F3D9C2", "#E2BFA2"),
    "s2": ("#E6BE9A", "#D1A27C"),
    "s3": ("#C99467", "#B07C52"),
    "s4": ("#9A6644", "#7F5235"),
    "s5": ("#6E4630", "#573623"),
}
HAIR = {"black": "#1E1A18", "brown": "#3B2A20", "grey": "#9AA0AB", "white": "#E4E6EA"}

BACKGROUNDS = {  # inner, outer of the medallion
    "ice": (C["white"], C["sky100"]),
    "sky": (C["sky100"], C["sky200"]),
    "sand": (C["cream"], C["gold100"]),
    "mist": (C["ice"], C["mist"]),
    "night": (C["lapis"], C["navy"]),
    "gold": (C["gold100"], C["gold200"]),
}


def shade(hex_color: str, k: float) -> str:
    """k < 0 darkens, k > 0 lightens."""
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    if k < 0:
        r, g, b = (int(v * (1 + k)) for v in (r, g, b))
    else:
        r, g, b = (int(v + (255 - v) * k) for v in (r, g, b))
    return f"#{r:02X}{g:02X}{b:02X}"


# ----------------------------------------------------------------------------- spec


@dataclass
class Avatar:
    id: str
    gender: str                    # "m" | "f"
    ar: str
    en: str
    bg: str = "ice"
    skin: str = "s2"
    garment: str = C["navy"]
    head: str = "kufi"             # m: kufi, ghutra, imama, hair ; f: hijab, khimar, niqab, shayla
    head_color: str = C["white"]
    accent: str = C["gold"]        # underscarf / agal / band
    beard: str | None = None       # full, short, trimmed, None
    hair: str = "black"
    young: bool = False
    extras: list[str] = field(default_factory=list)  # "glasses"


# ----------------------------------------------------------------------------- drawing


def defs(a: Avatar) -> str:
    inner, outer = BACKGROUNDS[a.bg]
    sk, sk_sh = SKIN[a.skin]
    g = a.garment
    return f"""
  <defs>
    <clipPath id="c"><circle cx="256" cy="256" r="256"/></clipPath>
    <radialGradient id="bg" cx="38%" cy="30%" r="80%">
      <stop offset="0" stop-color="{inner}"/><stop offset="1" stop-color="{outer}"/>
    </radialGradient>
    <radialGradient id="skin" cx="42%" cy="36%" r="70%">
      <stop offset="0" stop-color="{shade(sk, 0.12)}"/><stop offset=".65" stop-color="{sk}"/><stop offset="1" stop-color="{sk_sh}"/>
    </radialGradient>
    <linearGradient id="garment" x1="0" y1="0" x2=".35" y2="1">
      <stop offset="0" stop-color="{shade(g, 0.16)}"/><stop offset="1" stop-color="{shade(g, -0.18)}"/>
    </linearGradient>
    <linearGradient id="cover" x1=".1" y1="0" x2=".6" y2="1">
      <stop offset="0" stop-color="{shade(a.head_color, 0.14)}"/><stop offset="1" stop-color="{shade(a.head_color, -0.12)}"/>
    </linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity=".35"/><stop offset=".5" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
  </defs>"""


def background() -> str:
    return '<rect width="512" height="512" fill="url(#bg)"/>'


def shoulders(a: Avatar, scale: float = 1.0) -> str:
    # wide, calm shoulders; a soft collar line for the thobe
    top = 392 if not a.young else 404
    p = f"M40 520 C52 {top+44} 140 {top+4} 256 {top} C372 {top+4} 460 {top+44} 472 520 Z"
    out = f'<path d="{p}" fill="url(#garment)"/>'
    if a.gender == "m":
        out += (f'<path d="M222 {top+2} Q256 {top+34} 290 {top+2}" fill="none" stroke="{shade(a.garment, -0.3)}" '
                f'stroke-width="4" stroke-linecap="round" opacity=".55"/>')
        out += f'<path d="M256 {top+30} L256 520" stroke="{shade(a.garment, -0.28)}" stroke-width="3" opacity=".35"/>'
    return out


def neck(a: Avatar) -> str:
    sk, sk_sh = SKIN[a.skin]
    return (f'<path d="M226 318 L226 398 Q256 416 286 398 L286 318 Z" fill="{sk_sh}"/>'
            f'<path d="M226 350 Q256 372 286 350 L286 330 L226 330 Z" fill="{shade(sk_sh, -0.1)}" opacity=".45"/>')


def head(a: Avatar, ears: bool = True) -> str:
    sk, sk_sh = SKIN[a.skin]
    ry = 86 if not a.young else 80
    out = ""
    if ears:
        out += (f'<ellipse cx="183" cy="262" rx="12" ry="20" fill="{sk_sh}"/>'
                f'<ellipse cx="329" cy="262" rx="12" ry="20" fill="{sk_sh}"/>')
    out += f'<ellipse cx="256" cy="252" rx="74" ry="{ry}" fill="url(#skin)"/>'
    return out


def hair_top(a: Avatar) -> str:
    h = HAIR[a.hair]
    return (f'<path d="M181 258 C172 176 214 150 256 150 C298 150 340 176 331 258 C322 214 300 196 256 196 '
            f'C212 196 190 214 181 258 Z" fill="{h}"/>')


def beard(a: Avatar) -> str:
    if not a.beard:
        return ""
    h = HAIR["white"] if a.hair == "white" else HAIR["grey"] if a.hair == "grey" else HAIR[a.hair]
    shapes = {
        "full": "M182 248 C182 326 214 378 256 382 C298 378 330 326 330 248 C318 300 294 318 256 318 C218 318 194 300 182 248 Z",
        "short": "M186 262 C190 324 220 362 256 364 C292 362 322 324 326 262 C312 302 290 314 256 314 C222 314 200 302 186 262 Z",
        "trimmed": "M192 286 C200 330 226 352 256 354 C286 352 312 330 320 286 C304 312 284 318 256 318 C228 318 208 312 192 286 Z",
    }
    out = f'<path d="{shapes[a.beard]}" fill="{h}"/>'
    out += f'<path d="M222 316 C232 300 280 300 290 316 C276 312 236 312 222 316 Z" fill="{h}"/>'  # moustache, joined to the beard
    return out


def glasses(a: Avatar) -> str:
    stroke = C["goldDeep"] if a.gender == "m" else C["navy600"]
    return (f'<g fill="none" stroke="{stroke}" stroke-width="4" opacity=".9">'
            f'<rect x="206" y="240" width="40" height="26" rx="10"/><rect x="266" y="240" width="40" height="26" rx="10"/>'
            f'<path d="M246 252 L266 252"/></g>')


# -- male head coverings


def kufi(a: Avatar) -> str:
    col = a.head_color
    return (f'<path d="M178 230 C176 166 216 142 256 142 C296 142 336 166 334 230 C306 216 284 212 256 212 '
            f'C228 212 206 216 178 230 Z" fill="url(#cover)"/>'
            f'<path d="M178 230 C206 216 228 212 256 212 C284 212 306 216 334 230" fill="none" '
            f'stroke="{shade(col, -0.22)}" stroke-width="5" stroke-linecap="round"/>'
            f'<path d="M206 170 C226 152 286 152 306 170" fill="none" stroke="{shade(col, -0.12)}" stroke-width="3" opacity=".6"/>'
            f'<path d="M192 196 C220 182 292 182 320 196" fill="none" stroke="{shade(col, -0.12)}" stroke-width="3" opacity=".6"/>')


def ghutra(a: Avatar, back: bool) -> str:
    col = a.head_color
    if back:  # the cloth falling behind the shoulders, both sides
        return (f'<path d="M176 210 C150 300 134 380 108 470 L196 476 C200 400 196 320 192 262 Z" fill="url(#cover)"/>'
                f'<path d="M336 210 C362 300 378 380 404 470 L316 476 C312 400 316 320 320 262 Z" fill="url(#cover)"/>'
                f'<path d="M150 330 C146 380 136 420 124 462" fill="none" stroke="{shade(col, -0.18)}" stroke-width="3" opacity=".5"/>'
                f'<path d="M362 330 C366 380 376 420 388 462" fill="none" stroke="{shade(col, -0.18)}" stroke-width="3" opacity=".5"/>')
    agal = C["midnight"]
    return (f'<path d="M168 246 C162 160 208 128 256 128 C304 128 350 160 344 246 C322 214 292 202 256 202 '
            f'C220 202 190 214 168 246 Z" fill="url(#cover)"/>'
            f'<path d="M190 170 C214 150 298 150 322 170" fill="none" stroke="{shade(col, -0.15)}" stroke-width="3" opacity=".5"/>'
            f'<path d="M182 186 C206 160 306 160 330 186" fill="none" stroke="{agal}" stroke-width="10" stroke-linecap="round"/>'
            f'<path d="M180 202 C206 176 306 176 332 202" fill="none" stroke="{agal}" stroke-width="10" stroke-linecap="round"/>')


def imama(a: Avatar, back: bool) -> str:
    col = a.head_color
    if back:  # the tail («العذبة») over one shoulder
        return (f'<path d="M300 200 C330 260 334 330 326 410 L356 414 C368 330 360 250 322 196 Z" '
                f'fill="{shade(col, -0.08)}"/>')
    out = (f'<path d="M172 232 C164 150 212 116 256 116 C300 116 348 150 340 232 C316 214 290 208 256 208 '
           f'C222 208 196 214 172 232 Z" fill="url(#cover)"/>')
    for y, o in [(148, .55), (172, .5), (196, .45)]:
        out += (f'<path d="M{178 if y > 150 else 196} {y+18} C{214} {y-8} {300} {y-14} {336 if y > 150 else 318} {y}" '
                f'fill="none" stroke="{shade(col, -0.2)}" stroke-width="4" stroke-linecap="round" opacity="{o}"/>')
    return out


# -- female head coverings


def hijab(a: Avatar, kind: str) -> str:
    col = a.head_color
    sk, _ = SKIN[a.skin]
    if kind == "khimar":   # longer, covers shoulders and chest in one soft cape
        outer = ("M256 150 C184 150 160 204 160 266 C160 334 168 376 182 404 C130 422 78 458 58 520 "
                 "L454 520 C434 458 382 422 330 404 C344 376 352 334 352 266 C352 204 328 150 256 150 Z")
    else:
        outer = ("M256 152 C190 152 166 204 166 266 C166 330 174 368 190 394 C138 408 90 446 72 520 "
                 "L440 520 C422 446 374 408 322 394 C338 368 346 330 346 266 C346 204 322 152 256 152 Z")
    face = "M256 178 C214 178 194 214 194 258 C194 310 222 344 256 344 C290 344 318 310 318 258 C318 214 298 178 256 178 Z"
    out = (f'<path d="{outer} {face}" fill="url(#cover)" fill-rule="evenodd" '
           f'stroke="{shade(col, -0.32)}" stroke-width="2.5" stroke-opacity=".45"/>')
    out += f'<path d="{face}" fill="url(#skin)"/>'
    if kind == "niqab":    # lower face covered, only a calm band of skin at the eyes (no features)
        out += (f'<path d="M188 272 C210 280 236 282 256 282 C276 282 302 280 324 272 L330 352 C300 372 212 372 182 352 Z" '
                f'fill="url(#cover)"/>'
                f'<path d="M188 272 C210 280 236 282 256 282 C276 282 302 280 324 272" fill="none" '
                f'stroke="{shade(col, -0.25)}" stroke-width="3" opacity=".55"/>')
    # underscarf band at the forehead
    out += (f'<path d="M196 236 C204 198 230 186 256 186 C282 186 308 198 316 236 C298 214 280 206 256 206 '
            f'C232 206 214 214 196 236 Z" fill="{a.accent}"/>')
    # inner rim shadow so the cloth reads as wrapping the face
    out += (f'<path d="{face}" fill="none" stroke="{shade(col, -0.28)}" stroke-width="5" opacity=".35"/>')
    if kind in ("hijab", "niqab"):  # the wrapped fold crossing the chest
        out += (f'<path d="M318 392 C352 404 380 440 390 520 L338 520 C334 462 312 424 280 404 Z" '
                f'fill="{shade(col, -0.16)}" opacity=".9"/>')
    if kind == "shayla":   # the long end draped over the opposite shoulder
        out += (f'<path d="M196 396 C236 420 300 424 356 400 C372 440 382 480 386 520 L300 520 '
                f'C296 470 260 440 196 396 Z" fill="{shade(col, -0.12)}"/>')
    if kind == "khimar":
        out += (f'<path d="M184 386 C214 410 298 410 328 386" fill="none" stroke="{shade(col, -0.22)}" '
                f'stroke-width="4" opacity=".45"/>')
    out += f'<path d="{outer}" fill="url(#sheen)" opacity=".5"/>'
    return out


def render(a: Avatar) -> str:
    body = ""
    if a.gender == "m":
        if a.head == "ghutra":
            body += ghutra(a, back=True)
        if a.head == "imama":
            body += imama(a, back=True)
        body += shoulders(a) + neck(a) + head(a, ears=a.head not in ("ghutra",))
        if a.head in ("kufi", "hair"):
            body += hair_top(a)
        body += beard(a)
        body += {"kufi": kufi, "hair": lambda _a: "", "ghutra": lambda _a: ghutra(_a, back=False),
                 "imama": lambda _a: imama(_a, back=False)}[a.head](a)
    else:
        body += shoulders(a) + neck(a)
        body += hijab(a, a.head)
    if "glasses" in a.extras:
        body += glasses(a)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
            f'{defs(a)}<g clip-path="url(#c)">{background()}'
            f'<g transform="translate(256 292) scale(1.12) translate(-256 -270)">{body}</g></g></svg>\n')


# ----------------------------------------------------------------------------- the set


AVATARS: list[Avatar] = [
    # --- men
    Avatar("m01", "m", "طاقية بيضاء", "White kufi", bg="ice", skin="s2", garment=C["navy"], head="kufi",
           head_color=C["white"], beard="full", hair="black"),
    Avatar("m02", "m", "غترة وعقال", "Ghutra & agal", bg="sand", skin="s3", garment=C["white"], head="ghutra",
           head_color=C["white"], beard="short", hair="black"),
    Avatar("m03", "m", "عمامة", "Imama", bg="mist", skin="s4", garment=C["lapis"], head="imama",
           head_color=C["cream"], beard="full", hair="black"),
    Avatar("m04", "m", "لحية مشذّبة", "Trimmed beard", bg="sky", skin="s1", garment=C["lapis500"], head="hair",
           beard="trimmed", hair="brown"),
    Avatar("m05", "m", "طاقية ذهبية", "Gold kufi", bg="night", skin="s3", garment=C["midnight"], head="kufi",
           head_color=C["goldLight"], beard="short", hair="black"),
    Avatar("m06", "m", "شاب", "Young", bg="ice", skin="s2", garment=C["sky"], head="kufi",
           head_color=C["white"], beard=None, hair="black", young=True),
    Avatar("m07", "m", "شيخ وقور", "Elder", bg="gold", skin="s2", garment=C["navy600"], head="kufi",
           head_color=C["white"], beard="full", hair="white", extras=["glasses"]),
    Avatar("m08", "m", "عمامة كحلية", "Navy imama", bg="sand", skin="s5", garment=C["cream"], head="imama",
           head_color=C["navy"], beard="short", hair="black"),
    # --- women
    Avatar("f01", "f", "حجاب كحلي", "Navy hijab", bg="ice", skin="s2", garment=C["midnight"], head="hijab",
           head_color=C["navy"], accent=C["gold"]),
    Avatar("f02", "f", "حجاب سماوي", "Sky hijab", bg="sand", skin="s1", garment=C["sky200"], head="hijab",
           head_color=C["sky"], accent=C["white"]),
    Avatar("f03", "f", "خمار", "Khimar", bg="mist", skin="s3", garment=C["midnight"], head="khimar",
           head_color=C["navy600"], accent=C["sky200"]),
    Avatar("f04", "f", "نقاب", "Niqab", bg="gold", skin="s3", garment=C["navy"], head="niqab",
           head_color=C["midnight"], accent=C["navy600"]),
    Avatar("f05", "f", "شيلة ذهبية", "Gold shayla", bg="night", skin="s2", garment=C["cream"], head="shayla",
           head_color=C["goldLight"], accent=C["white"]),
    Avatar("f06", "f", "حجاب أبيض", "White hijab", bg="sky", skin="s4", garment=C["lapis"], head="hijab",
           head_color=C["white"], accent=C["sky200"]),
    Avatar("f07", "f", "فتاة", "Young", bg="ice", skin="s2", garment=C["lapis300"], head="hijab",
           head_color=C["gold200"], accent=C["white"], young=True),
    Avatar("f08", "f", "سيدة وقورة", "Elder", bg="sand", skin="s1", garment=C["navy400"], head="khimar",
           head_color=C["porcelain"], accent=C["mist"], extras=["glasses"]),
]


def main() -> None:
    out_master = HERE / "svg"
    out_app = ROOT / "apps/mobile/assets/avatars"
    for d in (out_master, out_app):
        d.mkdir(parents=True, exist_ok=True)
    for a in AVATARS:
        svg = render(a)
        (out_master / f"{a.id}.svg").write_text(svg)
    catalogue = [{"id": a.id, "gender": a.gender, "ar": a.ar, "en": a.en} for a in AVATARS]
    (HERE / "avatars.json").write_text(json.dumps(catalogue, ensure_ascii=False, indent=2) + "\n")
    subprocess.run(["node", str(HERE / "render_png.js"), str(out_master), str(out_app)], check=True)
    from PIL import Image  # PNG → WebP: smooth gradients (no banding) at ~12 KB each
    for png in sorted(out_app.glob("*.png")):
        Image.open(png).convert("RGBA").save(png.with_suffix(".webp"), "WEBP", quality=92, method=6, alpha_quality=100)
        png.unlink()
    print(f"{len(AVATARS)} avatars → {out_master} (svg) and {out_app} (webp)")


if __name__ == "__main__":
    main()

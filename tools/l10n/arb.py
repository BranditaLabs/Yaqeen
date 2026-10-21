#!/usr/bin/env python3
"""Add or update strings in apps/mobile/lib/l10n/app_{ar,en}.arb from a JSON spec.

    python3 tools/l10n/arb.py strings.json

strings.json: {"key": ["Arabic", "English", {"placeholder": "type"}?], ...}
Arabic is the template (app_ar.arb). Keys keep insertion order; existing keys are replaced in place.
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

L10N = pathlib.Path(__file__).resolve().parents[2] / "apps/mobile/lib/l10n"


def load(lang: str) -> dict:
    return json.loads((L10N / f"app_{lang}.arb").read_text(encoding="utf-8"))


def save(lang: str, data: dict) -> None:
    (L10N / f"app_{lang}.arb").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main(path: str) -> None:
    spec = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    ar, en = load("ar"), load("en")
    for key, value in spec.items():
        text_ar, text_en, *rest = value
        placeholders = rest[0] if rest else {}
        for name in set(re.findall(r"\{(\w+)\}", text_ar)) | set(re.findall(r"\{(\w+)\}", text_en)):
            placeholders.setdefault(name, "String")
        for data, text in ((ar, text_ar), (en, text_en)):
            data[key] = text
            if placeholders:
                data[f"@{key}"] = {"placeholders": {n: {"type": t} for n, t in placeholders.items()}}
            else:
                data.pop(f"@{key}", None)
    save("ar", ar)
    save("en", en)
    print(f"{len(spec)} strings → app_ar.arb / app_en.arb ({sum(1 for k in ar if not k.startswith('@'))} total)")


if __name__ == "__main__":
    main(sys.argv[1])

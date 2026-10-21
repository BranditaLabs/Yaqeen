"""Download an npm tarball, verify its pinned sha512 integrity, and return its files.

Shared by tools/quran/build_quran.py and tools/geo/build_cities.py. Stdlib only.
"""
from __future__ import annotations

import base64
import hashlib
import io
import tarfile
import urllib.request


def fetch(url: str, integrity: str) -> dict[str, bytes]:
    algo, _, expected = integrity.partition("-")
    if algo != "sha512":
        raise SystemExit(f"unsupported integrity {algo}")
    with urllib.request.urlopen(url, timeout=120) as res:  # noqa: S310 — pinned registry URL
        blob = res.read()
    actual = base64.b64encode(hashlib.sha512(blob).digest()).decode()
    if actual != expected:
        raise SystemExit(f"integrity mismatch for {url}\n  expected {expected}\n  actual   {actual}")
    files: dict[str, bytes] = {}
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        for member in tar.getmembers():
            if member.isfile():
                f = tar.extractfile(member)
                if f is not None:
                    files[member.name] = f.read()
    return files

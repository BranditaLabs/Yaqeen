"""Python port of the app's word alignment (apps/mobile/lib/features/recite/domain/recitation.dart).

Kept line-for-line equivalent so the ship-gate number measures what the app shows: same
normalisation (tashkeel stripped, alef forms unified, dagger alef read as alef), same tolerance (one
edit for words of 4+ letters), same Levenshtein over words and the same tie rule. A change to
`RecitationAligner` must be mirrored here (tools/asr/eval/test_aligner.py checks the shared cases).
"""

from __future__ import annotations

import re

# ArabicText._marks: U+0610–U+061A, U+064B–U+065F, U+0670, U+06D6–U+06ED, U+08D3–U+08FF
_MARKS = re.compile("[ؐ-ًؚ-ٰٟۖ-ۭ࣓-ࣿ]")
_EASTERN = "٠١٢٣٤٥٦٧٨٩"
_FOLD = {"أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ٲ": "ا", "ٳ": "ا", "ة": "ه", "ى": "ي", "ؤ": "و", "ئ": "ي", "ـ": ""}
# RecitationAligner._isMark: pause / sajda signs, ayah-end ornaments, digits.
_IS_MARK = re.compile("^[ۖ-ۭ۝۞٠-٩﴾﴿0-9]+$")
_NON_LETTER = re.compile("[^ء-ي]")


def normalize(text: str) -> str:
    out = []
    for c in _MARKS.sub("", text):
        d = _EASTERN.find(c)
        if d >= 0:
            out.append(str(d))
        else:
            out.append(_FOLD.get(c, c.lower()))
    return re.sub(r"\s+", " ", "".join(out)).strip()


def words(text: str) -> list[str]:
    return [w for w in re.split(r"\s+", text) if w and not _IS_MARK.match(w)]


def _norm(w: str) -> str:
    return _NON_LETTER.sub("", normalize(w.replace("ٰ", "ا")))


def _edit(a: str, b: str) -> int:
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (0 if a[i - 1] == b[j - 1] else 1))
        prev = cur
    return prev[len(b)]


def same(a: str, b: str) -> bool:
    x, y = _norm(a), _norm(b)
    if x == y:
        return True
    if len(x) < 4 or len(y) < 4:
        return False
    return _edit(x, y) <= 1


OK, WARN, SKIPPED = "ok", "warn", "skipped"


def align(expected: list[str], heard: list[str]) -> list[str]:
    """Marks every expected word: ok / warn / skipped (RecitationAligner.align)."""
    n, m = len(expected), len(heard)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        dp[i][0] = i
    for j in range(m + 1):
        dp[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            sub = dp[i - 1][j - 1] + (0 if same(expected[i - 1], heard[j - 1]) else 1)
            dele = dp[i - 1][j] + 1
            ins = dp[i][j - 1] + 1
            dp[i][j] = (sub if sub < ins else ins) if sub < dele else (dele if dele < ins else ins)
    marks = [SKIPPED] * n
    i, j = n, m
    while i > 0 and j > 0:
        match = same(expected[i - 1], heard[j - 1])
        if match and dp[i][j] == dp[i - 1][j - 1]:
            marks[i - 1] = OK
            i -= 1
            j -= 1
        elif dp[i][j] == dp[i - 1][j] + 1:
            marks[i - 1] = SKIPPED
            i -= 1
        elif dp[i][j] == dp[i - 1][j - 1] + 1:
            marks[i - 1] = WARN
            i -= 1
            j -= 1
        else:
            j -= 1
    return marks

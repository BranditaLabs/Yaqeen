"""Keeps aligner.py in step with the app's RecitationAligner (same cases as
apps/mobile/test/features/hifz_recite_test.dart). Run: python -m pytest tools/asr/eval  (or plain python)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aligner  # noqa: E402

FATIHA_2 = "ٱلۡحَمۡدُ لِلَّهِ رَبِّ ٱلۡعَٰلَمِينَ"


def test_words_drop_marks():
    assert aligner.words("ذَٰلِكَ ٱلۡكِتَٰبُ لَا رَيۡبَۛ فِيهِۛ") == ["ذَٰلِكَ", "ٱلۡكِتَٰبُ", "لَا", "رَيۡبَۛ", "فِيهِۛ"]
    assert aligner.words("هُدٗى ۖ ١٢") == ["هُدٗى"]


def test_dagger_alef_and_one_slip():
    assert aligner.same("ٱلۡعَٰلَمِينَ", "العالمين")
    assert aligner.same("ٱلۡعَٰلَمِينَ", "العالمن")  # one letter missing, 4+ letters
    assert aligner.same("رَبِّ", "رب")
    assert not aligner.same("رَبِّ", "رد")  # short words must match exactly


def test_align_marks():
    exp = aligner.words(FATIHA_2)
    assert aligner.align(exp, ["الحمد", "لله", "رب", "العالمين"]) == ["ok"] * 4
    assert aligner.align(exp, ["الحمد", "لله", "رب"]) == ["ok", "ok", "ok", "skipped"]
    assert aligner.align(exp, ["الحمد", "لله", "ملك", "العالمين"]) == ["ok", "ok", "warn", "ok"]


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")

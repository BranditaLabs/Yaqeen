import 'package:flutter/material.dart';

import '../../../core/design/motion.dart';
import '../../../core/format.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../quran/domain/quran_data.dart';
import '../../recite/domain/recitation.dart';
import '../domain/recording_models.dart';

/// How one word of the chosen verses is drawn.
enum WordLook {
  /// Not reached yet: ink.
  plain,

  /// Recited / played: lapis.
  lit,

  /// The word being recited or played now: lapis on a soft lapis wash.
  current,

  /// Not heard (or heard differently) once the voice was past it: ink with a quiet underline —
  /// never red, never «خطأ».
  skipped,
}

/// The chosen ayat set large in the mushaf font (Amiri Quran, the bundled text — never altered),
/// centred, word by word, so a recorder can light words as they are recited and a listener can
/// follow `words` timings (karaoke). A word changes colour over 280 ms (at once under reduce
/// motion); [follow] keeps the current word in view of the nearest scrollable.
class VerseWordsView extends StatefulWidget {
  const VerseWordsView({
    super.key,
    required this.ayat,
    required this.lookOf,
    this.fontSize = 30,
    this.current,
    this.follow = false,
    this.semanticsLabel,
  });

  final List<(AyahRef, String)> ayat;

  /// The look of the [index]-th word ([RecitationAligner.words] numbering) of [ayah].
  final WordLook Function(int ayah, int index) lookOf;
  final double fontSize;

  /// The word to keep in view (ayah, index) when [follow].
  final (int, int)? current;
  final bool follow;
  final String? semanticsLabel;

  @override
  State<VerseWordsView> createState() => _VerseWordsViewState();
}

class _VerseWordsViewState extends State<VerseWordsView> {
  final Map<(int, int), GlobalKey> _keys = {};

  @override
  void didUpdateWidget(VerseWordsView old) {
    super.didUpdateWidget(old);
    if (widget.follow && widget.current != null && widget.current != old.current) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    final key = _keys[widget.current];
    final ctx = key?.currentContext;
    if (ctx == null || !mounted) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: motionOr(context, Motion.emphasised),
      curve: Motion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    final base = YqText.quran(size: widget.fontSize, height: 2.2, color: YqColors.ink);
    final spans = <InlineSpan>[];
    for (final (ref, text) in widget.ayat) {
      var index = 0;
      for (final token in text.split(' ')) {
        if (token.isEmpty) continue;
        if (RecitationAligner.words(token).isEmpty) {
          // A pause or sajda sign inside the ayah: drawn with the text, never counted.
          spans.add(TextSpan(text: '$token ', style: base.copyWith(color: YqColors.muted)));
          continue;
        }
        final i = index++;
        final look = widget.lookOf(ref.ayah, i);
        final key = _keys.putIfAbsent((ref.ayah, i), GlobalKey.new);
        spans
          ..add(
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: VerseWord(key: key, text: token, look: look, base: base, still: still),
            ),
          )
          ..add(TextSpan(text: ' ', style: base));
      }
      spans.add(
        TextSpan(
          text: '﴿${YqFormat.toArabicIndic(ref.ayah)}﴾ ',
          style: base.copyWith(color: YqColors.muted, fontSize: widget.fontSize * 0.8),
          semanticsLabel: '',
        ),
      );
    }
    return Semantics(
      label: widget.semanticsLabel,
      child: MediaQuery.withNoTextScaling(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Text.rich(TextSpan(children: spans), textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// One word of [VerseWordsView] (public so tests can read its [look]).
class VerseWord extends StatelessWidget {
  const VerseWord({super.key, required this.text, required this.look, required this.base, required this.still});
  final String text;
  final WordLook look;
  final TextStyle base;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final lit = look == WordLook.lit || look == WordLook.current;
    final style = base.copyWith(
      color: lit ? YqColors.lapis : YqColors.ink,
      decoration: look == WordLook.skipped ? TextDecoration.underline : TextDecoration.none,
      decorationColor: YqColors.ink.withValues(alpha: 0.45),
      decorationThickness: 1.4,
    );
    return AnimatedContainer(
      duration: still ? Duration.zero : Motion.standard,
      curve: Motion.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: look == WordLook.current ? YqColors.lapis.withValues(alpha: 0.08) : YqColors.lapis.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AnimatedDefaultTextStyle(
        duration: still ? Duration.zero : Motion.standard,
        curve: Motion.easeOut,
        style: style,
        child: Text(text, textDirection: TextDirection.rtl),
      ),
    );
  }
}

/// Karaoke from verified (or on-device) timings: which word is playing at [position].
abstract final class Karaoke {
  /// The look of each word for a clip at [position]: words that ended are lit, the one whose
  /// window holds [position] is current, the rest plain. Words without timings stay plain.
  static WordLook lookAt(List<RecordingWord>? words, Duration position, int ayah, int index, {bool started = true}) {
    if (words == null || !started) return WordLook.plain;
    final ms = position.inMilliseconds;
    for (final w in words) {
      if (w.ayah != ayah || w.index != index) continue;
      if (ms >= w.endMs) return WordLook.lit;
      if (ms >= w.startMs) return WordLook.current;
      return WordLook.plain;
    }
    return WordLook.plain;
  }

  /// The word playing at [position] (for keeping it in view), if any.
  static (int, int)? currentAt(List<RecordingWord>? words, Duration position) {
    if (words == null) return null;
    final ms = position.inMilliseconds;
    RecordingWord? best;
    for (final w in words) {
      if (w.startMs <= ms && (best == null || w.startMs >= best.startMs)) best = w;
    }
    return best == null ? null : (best.ayah, best.index);
  }
}

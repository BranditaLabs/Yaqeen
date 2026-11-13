import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/domain/avatar.dart';
import '../../l10n/gen/app_localizations.dart';
import '../di/providers.dart';
import '../format.dart';
import '../theme/tokens.dart';
import 'yq_ring.dart';
import 'yq_states.dart';

/// A profile picture in a circle (docs/DESIGN_SYSTEM.md §4): a preset from the bundled art, a
/// photo, or the person's initial in ink on ice. Bundled presets and this phone's files load
/// directly; the caller's own photo (an authed `/v1/me/…` path) loads through `ApiClient.getBytes`
/// and is kept in memory; other people's photos use `Image.network` at the drawn size. Until the
/// first frame it shows a skeleton circle (shimmering when inside a `YqSkeleton`); a photo that
/// fails falls back to the initial. A thin white rim lifts it off glass.
class YqAvatar extends ConsumerStatefulWidget {
  const YqAvatar({super.key, required this.avatar, this.size = 40, this.name, this.rim = true, this.semanticLabel});

  final AvatarRef avatar;
  final double size;

  /// The person's name: the initial's letter and the semantics label.
  final String? name;
  final bool rim;

  /// Overrides the default «صورة {name}».
  final String? semanticLabel;

  /// The caller's own photo bytes, by URL + photo id (cleared on sign-out with [clearMemoryCache]).
  static final Map<String, Uint8List> _memory = {};

  static void clearMemoryCache() => _memory.clear();

  @override
  ConsumerState<YqAvatar> createState() => _YqAvatarState();
}

class _YqAvatarState extends ConsumerState<YqAvatar> {
  Uint8List? _bytes;
  bool _failed = false;
  String? _loadingKey;

  String _key(PhotoAvatar p) => '${p.id}|${widget.size <= 96 ? p.smallUrl : p.url}';

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(YqAvatar old) {
    super.didUpdateWidget(old);
    if (old.avatar != widget.avatar || old.size != widget.size) {
      _bytes = null;
      _failed = false;
      _maybeLoad();
    }
  }

  /// Only an authed photo with no local file needs the API.
  void _maybeLoad() {
    final a = widget.avatar;
    if (a is! PhotoAvatar || !a.isAuthedPath || _hasLocalFile(a)) return;
    final key = _key(a);
    final hit = YqAvatar._memory[key];
    if (hit != null) {
      _bytes = hit;
      return;
    }
    _loadingKey = key;
    final path = widget.size <= 96 ? a.smallUrl : a.url;
    ref.read(apiClientProvider).getBytes(path).then(
      (bytes) {
        YqAvatar._memory[key] = bytes;
        if (mounted && _loadingKey == key) setState(() => _bytes = bytes);
      },
      onError: (Object _) {
        if (mounted && _loadingKey == key) setState(() => _failed = true);
      },
    );
  }

  static bool _hasLocalFile(PhotoAvatar a) => a.localPath != null && File(a.localPath!).existsSync();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final size = widget.size;
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final initial = _Initial(name: widget.name, size: size);
    final skeleton = YqSkeletonBox.circle(size);

    Widget frame(ImageProvider provider) => Image(
          image: ResizeImage.resizeIfNeeded(px, px, provider),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : skeleton,
          errorBuilder: (context, _, __) => initial,
        );

    final a = widget.avatar;
    final Widget content = switch (a) {
      InitialAvatar() => initial,
      PresetAvatar() => frame(AssetImage(a.asset)),
      PhotoAvatar() when _hasLocalFile(a) => frame(FileImage(File(a.localPath!))),
      PhotoAvatar() when a.isAuthedPath => _failed ? initial : (_bytes == null ? skeleton : frame(MemoryImage(_bytes!))),
      PhotoAvatar() when a.url.isNotEmpty => frame(NetworkImage(size <= 96 ? a.smallUrl : a.url)),
      PhotoAvatar() => initial,
    };

    final name = widget.name?.trim();
    final label = widget.semanticLabel ??
        (name == null || name.isEmpty ? null : (a is InitialAvatar ? t.avInitialSemantics(name) : t.avSemantics(name)));
    final rim = widget.rim ? (size / 28).clamp(1.0, 3.0) : 0.0;
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: YqColors.ice,
            border: rim > 0 ? Border.all(color: YqColors.white, width: rim, strokeAlign: BorderSide.strokeAlignInside) : null,
          ),
          child: ClipOval(child: content),
        ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial({required this.name, required this.size});
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = name?.trim() ?? '';
    final letter = n.isEmpty ? '' : String.fromCharCode(n.runes.first);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: YqColors.ice,
      child: Text(
        letter,
        // A picture, not text: it keeps its size at any text scale.
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontFamily: 'Tajawal', fontSize: size * 0.42, height: 1.1, fontWeight: FontWeight.w700, color: YqColors.ink),
      ),
    );
  }
}

/// An avatar inside the level ring: lapis on a soft lapis track; [achieved] (the top level, or a
/// level just reached) turns it gold and plays one 600 ms glint — skipped under reduce-motion.
/// [showLevel] adds the level numeral at the bottom end. [ring] false draws the avatar alone
/// (guests). Public rings use the nightly snapshot; the caller's own ring is live.
class YqLevelAvatar extends StatelessWidget {
  const YqLevelAvatar({
    super.key,
    required this.avatar,
    required this.level,
    required this.progress,
    this.size = 48,
    this.stroke = 2.5,
    this.achieved = false,
    this.showLevel = false,
    this.ring = true,
    this.name,
    this.levelName,
    this.semanticLabel,
  });

  final AvatarRef avatar;
  final int level;
  final double progress;
  final double size;
  final double stroke;
  final bool achieved;
  final bool showLevel;
  final bool ring;
  final String? name;

  /// For the default semantics «المستوى {n} · {name}، {percent}%».
  final String? levelName;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (!ring) return YqAvatar(avatar: avatar, size: size, name: name, semanticLabel: semanticLabel);
    // The ring is drawn 1 pt in from the edge; leave a clear gap between it and the picture.
    final inner = size - 2 * (stroke + 1 + (size >= 64 ? 3.0 : 2.0));
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final ringLabel = t.lvlRingSemantics(YqFormat.number(level), levelName ?? '', YqFormat.number(percent));
    final label = semanticLabel ?? [if (name != null && name!.trim().isNotEmpty) name!.trim(), ringLabel].join('، ');
    final badge = (size * 0.32).clamp(16.0, 30.0);
    return Semantics(
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              YqRing(
                value: progress,
                size: size,
                stroke: stroke,
                color: achieved ? YqColors.gold : YqColors.lapis,
                track: achieved ? YqColors.gold.withValues(alpha: 0.25) : YqColors.lapis100.withValues(alpha: 0.5),
                glint: achieved,
              ),
              YqAvatar(avatar: avatar, size: inner.clamp(8.0, size), name: name, rim: false),
              if (showLevel)
                PositionedDirectional(
                  end: -1,
                  bottom: -1,
                  child: Container(
                    width: badge,
                    height: badge,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: YqColors.white,
                      border: Border.all(color: achieved ? YqColors.gold : YqColors.lapis, width: 1.5),
                    ),
                    child: Text(
                      YqFormat.number(level),
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: 'Jost',
                        fontSize: badge * 0.55,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: achieved ? YqColors.goldText : YqColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading rows for people lists (leagues, standings, the level board): a ringed disc, a name line
/// and a points pill. Put it inside one `YqSkeleton`.
class YqSkeletonAvatarRows extends StatelessWidget {
  const YqSkeletonAvatarRows({super.key, this.rows = 6, this.avatar = 36});
  final int rows;
  final double avatar;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: YqSpace.l, vertical: YqSpace.s),
              child: Row(
                children: [
                  const YqSkeletonBox(width: 20, height: 12, radius: YqRadii.pill),
                  const SizedBox(width: YqSpace.m),
                  YqSkeletonBox.circle(avatar),
                  const SizedBox(width: YqSpace.m),
                  Expanded(child: YqSkeletonLine(widthFactor: const [0.6, 0.45, 0.7, 0.52][i % 4], height: 13)),
                  const SizedBox(width: YqSpace.m),
                  const YqSkeletonBox(width: 44, height: 14, radius: YqRadii.pill),
                ],
              ),
            ),
        ],
      );
}

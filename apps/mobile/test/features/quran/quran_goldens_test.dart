import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/remote_config.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/recitation_engine.dart';
import 'package:yaqeen/core/settings/app_settings.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/listen/presentation/listen_controller.dart';
import 'package:yaqeen/features/listen/presentation/mini_player.dart';
import 'package:yaqeen/features/quran/domain/passage.dart';
import 'package:yaqeen/features/quran/presentation/quran_providers.dart';
import 'package:yaqeen/features/quran/presentation/reader_screen.dart';
import 'package:yaqeen/features/quran/presentation/session/mode_dock.dart';

import '../../helpers/fonts.dart';
import '../../helpers/harness.dart';
import 'one_page_fakes.dart';

/// Goldens of the «صفحة واحدة» dock in each layer and of the mini player, in Arabic and English.
/// They are generated on Linux only (`.github/workflows/goldens.yml`); never update them on Windows
/// or macOS, where fonts rasterise differently.
void main() {
  final q = loadQuran();
  final now = DateTime.utc(2026, 10, 20, 12);

  setUpAll(loadAppFonts);
  setUp(() => YqGlassConfig.enableBlur = false);

  const playing = ListenState(status: ListenStatus.ready, surah: 78, ayah: 4, playing: true, synced: true);

  List<Override> base(String locale, FakeListen listen) => [
        clockProvider.overrideWithValue(() => now),
        quranDataProvider.overrideWith((_) async => q),
        mushafLayoutProvider.overrideWith((_) async => null),
        listenControllerProvider.overrideWith(() => listen),
        recitationEngineProvider.overrideWithValue(ScriptedRecitationEngine()),
        initialConfigProvider.overrideWithValue(RemoteConfig(features: Map.of(RemoteConfig.defaultFeatures)..[Flags.recite] = true)),
        initialSettingsProvider.overrideWithValue(AppSettings(readerHintSeen: true, locale: locale)),
      ];

  for (final locale in ['ar', 'en']) {
    for (final mode in QuranMode.values) {
      testWidgets('dock golden: ${mode.name} ($locale)', (tester) async {
        tester.view.physicalSize = const Size(390, 844) * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final listen = FakeListen(mode == QuranMode.listen ? playing : const ListenState());
        await tester.pumpWidget(harness(ReaderScreen(initialPage: 582, mode: mode), locale: locale, overrides: base(locale, listen)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(find.byType(QuranModeDock), matchesGoldenFile('../../goldens/quran_dock_${mode.name}_$locale.png'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }

    testWidgets('mini player golden ($locale)', (tester) async {
      tester.view.physicalSize = const Size(390, 160) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        harness(
          const Scaffold(body: Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: MiniPlayer()))),
          locale: locale,
          overrides: base(locale, FakeListen(playing)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await expectLater(find.byType(MiniPlayer), matchesGoldenFile('../../goldens/mini_player_$locale.png'));
    });
  }
}

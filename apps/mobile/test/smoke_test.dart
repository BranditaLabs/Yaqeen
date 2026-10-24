import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/storage/kv_store.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/core/widgets/yq_icon.dart';
import 'package:yaqeen/main.dart';

void main() {
  setUp(() => YqGlassConfig.enableBlur = false);

  testWidgets('app boots in Arabic RTL with the floating tab bar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(MemoryKvStore()),
          secureStoreProvider.overrideWithValue(MemoryKvStore()),
        ],
        child: const YaqeenApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final dir = Directionality.of(tester.element(find.byType(Scaffold).first));
    expect(dir, TextDirection.rtl);
    expect(find.text('الرئيسية'), findsWidgets);
  });

  testWidgets('every icon paints in every tone', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          children: [
            for (final icon in YqIcons.values)
              for (final tone in YqIconTone.values) YqIcon(icon, tone: tone),
          ],
        ),
      ),
    );
    expect(find.byType(YqIcon), findsNWidgets(YqIcons.values.length * YqIconTone.values.length));
  });
}

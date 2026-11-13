import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/di/providers.dart';
import 'package:yaqeen/core/platform/device_services.dart';
import 'package:yaqeen/core/time/zoned.dart';
import 'package:yaqeen/core/widgets/liquid_glass.dart';
import 'package:yaqeen/features/onboarding/data/auth_repository.dart';
import 'package:yaqeen/features/profile/presentation/profile_screen.dart';

import '../helpers/fonts.dart';
import '../helpers/harness.dart';

/// Profile tab tests (moved unchanged from onboarding_profile_test.dart; the profile stream owns
/// this file from here).
void main() {
  setUpAll(() async {
    Zoned.ensureInitialized();
    await loadAppFonts();
  });
  setUp(() => YqGlassConfig.enableBlur = false);

  testWidgets('profile: guest sees the sign-in CTA and no destructive rows', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        overrides: [initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.guest, pendingServer: true))],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ضيف'), findsOneWidget);
    expect(find.text('سجّل الدخول لحفظ نقاطك'), findsOneWidget);
    expect(find.text('حذف الحساب'), findsNothing);
    expect(find.text('الخصوصية والموافقات'), findsOneWidget);
  });

  testWidgets('profile: «عن يقين» opens the Yaqeen website in the app language', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final device = FakeDeviceServices();
    await tester.pumpWidget(
      harness(
        const Scaffold(body: ProfileScreen()),
        overrides: [
          initialSessionProvider.overrideWithValue(const Session(provider: SignInProvider.guest, pendingServer: true)),
          deviceServicesProvider.overrideWithValue(device),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('عن يقين'));
    await tester.pump();
    expect(device.opened.single.toString(), 'https://yaqeenarabia.com/?lang=ar');
  });
}

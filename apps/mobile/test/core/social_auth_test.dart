import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/platform/social_auth.dart';

void main() {
  group('PluginSocialAuth.isGoogleSetupFailure', () {
    test('an unregistered signing key reported as a cancellation is a failure', () {
      expect(PluginSocialAuth.isGoogleSetupFailure('[16] Account reauth failed.'), isTrue);
      expect(PluginSocialAuth.isGoogleSetupFailure('Developer console is not set up correctly.'), isTrue);
    });

    test('the user closing the sheet stays a quiet cancellation', () {
      expect(PluginSocialAuth.isGoogleSetupFailure(null), isFalse);
      expect(PluginSocialAuth.isGoogleSetupFailure('activity is cancelled by the user.'), isFalse);
    });
  });
}

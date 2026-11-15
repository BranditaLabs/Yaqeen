import 'package:flutter_test/flutter_test.dart';
import 'package:yaqeen/core/config/env.dart';

void main() {
  test('forced update: Play on Android; the App Store listing on iOS, the get-app link until it exists', () {
    expect(
      Env.updateUri(ios: false, storeId: ''),
      Uri.parse('https://play.google.com/store/apps/details?id=com.yaqinbrand.yaqeen'),
    );
    expect(Env.updateUri(ios: true, storeId: '6470000000'), Uri.parse('https://apps.apple.com/app/id6470000000'));
    // No listing yet (unset, or the old '0' placeholder is not a real id): never a dead apps.apple.com page.
    expect(Env.updateUri(ios: true, storeId: '', site: 'https://yaqeenarabia.com'), Uri.parse('https://yaqeenarabia.com/get-app'));
    expect(Env.updateUri(ios: true, storeId: '0', site: 'https://yaqeenarabia.com'), Uri.parse('https://yaqeenarabia.com/get-app'));
    expect(Env.updateUri(ios: true, storeId: 'abc', site: 'https://yaqeenarabia.com'), Uri.parse('https://yaqeenarabia.com/get-app'));
  });
}

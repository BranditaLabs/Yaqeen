import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

/// The default Firebase app, started once and shared by push (FCM) and the Google ads sink, so the
/// two never race to initialise it. A failure is retried on the next call.
abstract final class FirebaseAppStarter {
  static Future<FirebaseApp>? _app;

  static Future<FirebaseApp> ensure() => _app ??= _start().catchError((Object e) {
        _app = null;
        throw e;
      });

  static Future<FirebaseApp> _start() async =>
      Firebase.apps.isEmpty ? Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform) : Firebase.app();
}

import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

class CloudRuntime {
  CloudRuntime._();
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      // `flutterfire configure` supplies the platform configuration. A
      // missing Firebase project must never prevent the local-first app from
      // launching, nor should it be papered over with invented credentials.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (_) {
      _initialized = false;
    }
  }
}

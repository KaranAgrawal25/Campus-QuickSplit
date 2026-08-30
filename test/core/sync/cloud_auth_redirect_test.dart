import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firebase email-link configuration is opt-in', () {
    expect(const String.fromEnvironment('FIREBASE_EMAIL_LINK_URL'), isEmpty);
  });
}

import 'package:campus_quicksplit/data/repositories/firebase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validates Firebase email/password credentials before network calls', () {
    expect(FirebaseAuthRepository.validateEmail('student@example.com'), isNull);
    expect(FirebaseAuthRepository.validateEmail('bad email'), isNotNull);
    expect(FirebaseAuthRepository.validatePassword('secure123'), isNull);
    expect(FirebaseAuthRepository.validatePassword('short'), isNotNull);
  });
}

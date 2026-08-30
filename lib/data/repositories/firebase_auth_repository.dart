import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Firebase Authentication adapter. Firebase project configuration is supplied
/// by FlutterFire, never embedded in source.
class FirebaseAuthRepository {
  FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;

  Future<bool> signInWithGoogle() async {
    try {
      final account = await GoogleSignIn(scopes: const ['email']).signIn();
      if (account == null) return false;
      final tokens = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );
      await _auth.signInWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_message(error));
    } catch (_) {
      throw const FirebaseAuthFailure(
        'Could not sign in with Google. Check your connection and try again',
      );
    }
  }

  bool get isSignedIn => _auth.currentUser != null;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  static String? validateEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())
      ? null
      : 'Enter a valid email address';

  static String? validatePassword(String password) =>
      password.length >= 8 ? null : 'Use at least 8 characters';

  Future<void> signIn({required String email, required String password}) async {
    _validateCredentials(email, password);
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_message(error));
    }
  }

  Future<void> createAccount({
    required String email,
    required String password,
  }) async {
    _validateCredentials(email, password);
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw FirebaseAuthFailure(_message(error));
    }
  }

  void _validateCredentials(String email, String password) {
    final emailError = validateEmail(email);
    final passwordError = validatePassword(password);
    if (emailError != null) throw FirebaseAuthFailure(emailError);
    if (passwordError != null) throw FirebaseAuthFailure(passwordError);
  }

  String _message(FirebaseAuthException error) => switch (error.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'Incorrect email or password',
    'email-already-in-use' => 'An account already uses this email',
    'network-request-failed' => 'Check your internet connection and try again',
    'too-many-requests' => 'Too many attempts. Please try again later',
    _ => 'We couldn’t sign you in right now. Please try again.',
  };

  Future<void> signOut() => _auth.signOut();
}

class FirebaseAuthFailure implements Exception {
  const FirebaseAuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

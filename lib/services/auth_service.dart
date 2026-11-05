import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Firebase Auth + Google sign-in.
/// Uses the Firebase project "Health Assistant" (health-assistant-65709);
/// Google provider enabled, support email testme900001@gmail.com.
///
/// NOTE: Google sign-in needs the release keystore's SHA-1 fingerprint
/// registered in Firebase console for release builds. Debug builds use the
/// debug keystore and work without it.
class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  String? get uid => _auth.currentUser?.uid;

  bool get isSignedIn => _auth.currentUser != null;

  /// Sign in with Google (Firebase Auth).
  /// Throws [AuthException] with a Burmese message on failure.
  Future<User> signInWithGoogle() async {
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
      );
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) throw AuthException('Google login မအောင်မြင်ပါ။');
      return user;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw AuthException('Login ကို ဖျက်လိုက်ပါသည်။');
      }
      throw AuthException('Google login မရပါ: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      throw AuthException('Login မရပါ: ${e.message ?? e.code}');
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

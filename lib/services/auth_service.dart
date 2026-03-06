import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
      _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  bool _googleInitialized = false;

  Stream<User?> authStateChanges() {
    return _firebaseAuth.authStateChanges();
  }

  User? get currentUser => _firebaseAuth.currentUser;

  Future<void> resolveRedirectResultIfNeeded() async {
    if (!kIsWeb) {
      return;
    }
    try {
      await _firebaseAuth.getRedirectResult();
    } catch (_) {
      // Ignore redirect-resolution errors to keep boot resilient.
    }
  }

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    if (kIsWeb) {
      await _signInWeb(provider);
      return;
    }

    try {
      await _firebaseAuth.signInWithProvider(provider);
      return;
    } on FirebaseAuthException {
      // Fall back to Google Sign-In SDK if native provider flow fails.
    }

    await _signInWithGoogleCredentials();
  }

  Future<void> _signInWeb(GoogleAuthProvider provider) async {
    try {
      await _firebaseAuth.signInWithPopup(provider);
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('popup') || code.contains('cancelled-popup-request')) {
        await _firebaseAuth.signInWithRedirect(provider);
        return;
      }
      rethrow;
    }
  }

  Future<void> _signInWithGoogleCredentials() async {
    if (!_googleInitialized) {
      await _googleSignIn.initialize(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _googleInitialized = true;
    }
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google ID token could not be acquired.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _firebaseAuth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Ignore and continue to Firebase sign-out.
      }
    }
    await _firebaseAuth.signOut();
  }
}

const String _serverClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    AuthServiceDependencies? dependencies,
    bool? isWeb,
  }) : _dependencies =
           dependencies ??
           AuthServiceDependencies.live(
             firebaseAuth: firebaseAuth ?? FirebaseAuth.instance,
             googleSignIn: googleSignIn ?? GoogleSignIn.instance,
           ),
       _isWeb = isWeb ?? kIsWeb;

  final AuthServiceDependencies _dependencies;
  final bool _isWeb;
  bool _googleInitialized = false;

  Stream<User?> authStateChanges() {
    return _dependencies.authStateChanges();
  }

  User? get currentUser => _dependencies.currentUser();

  Future<void> resolveRedirectResultIfNeeded() async {
    if (!_isWeb) {
      return;
    }
    try {
      await _dependencies.resolveRedirectResult();
    } catch (_) {
      // Ignore redirect-resolution errors to keep boot resilient.
    }
  }

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    if (_isWeb) {
      await _signInWeb(provider);
      return;
    }

    await _signInWithGoogleCredentials();
  }

  Future<void> _signInWeb(GoogleAuthProvider provider) async {
    try {
      await _dependencies.signInWithPopup(provider);
    } on FirebaseAuthException catch (error) {
      final code = error.code.toLowerCase();
      if (code.contains('popup') || code.contains('cancelled-popup-request')) {
        await _dependencies.signInWithRedirect(provider);
        return;
      }
      rethrow;
    }
  }

  Future<void> _signInWithGoogleCredentials() async {
    if (!_googleInitialized) {
      await _dependencies.initializeGoogleSignIn(
        serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
      );
      _googleInitialized = true;
    }
    final tokens = await _dependencies.authenticateWithGoogle();
    final idToken = tokens.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google ID token could not be acquired.');
    }

    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await _dependencies.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!_isWeb) {
      try {
        await _dependencies.signOutGoogle();
      } catch (_) {
        // Ignore and continue to Firebase sign-out.
      }
    }
    await _dependencies.signOutFirebase();
  }

  String describeSignInError(Object error) {
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.canceled:
          return 'Google ログインを完了できませんでした。'
              'アカウントの再認証に失敗したか、'
              'Android の Google サインイン設定が一致していない可能性があります。';
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'Google ログインを開始できませんでした。'
              'Android の Google サインイン設定を確認してください。';
        case GoogleSignInExceptionCode.interrupted:
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'Google ログインを完了できませんでした。'
              'アプリを開き直して再試行してください。';
        case GoogleSignInExceptionCode.userMismatch:
          return '選択した Google アカウントを確認して、もう一度ログインしてください。';
        case GoogleSignInExceptionCode.unknownError:
          return 'Google ログインに失敗しました。しばらくしてから再試行してください。';
      }
    }

    if (error is FirebaseAuthException) {
      return 'Google ログインに失敗しました。'
          'Firebase Authentication と Google サインイン設定を確認してください。';
    }

    if (error is StateError &&
        '$error' == 'Bad state: Google ID token could not be acquired.') {
      return 'Google ID トークンを取得できませんでした。'
          'Google サインイン設定を確認してください。';
    }

    return 'Google ログインに失敗しました。しばらくしてから再試行してください。';
  }
}

class GoogleAuthenticationTokens {
  const GoogleAuthenticationTokens({required this.idToken});

  final String? idToken;
}

typedef AuthStateChangesCallback = Stream<User?> Function();
typedef CurrentUserCallback = User? Function();
typedef ResolveRedirectResultCallback = Future<void> Function();
typedef PopupSignInCallback =
    Future<void> Function(GoogleAuthProvider provider);
typedef RedirectSignInCallback =
    Future<void> Function(GoogleAuthProvider provider);
typedef SignInWithCredentialCallback =
    Future<void> Function(AuthCredential credential);
typedef SignOutCallback = Future<void> Function();
typedef InitializeGoogleSignInCallback =
    Future<void> Function({String? serverClientId});
typedef AuthenticateWithGoogleCallback =
    Future<GoogleAuthenticationTokens> Function();

class AuthServiceDependencies {
  const AuthServiceDependencies({
    required this.authStateChanges,
    required this.currentUser,
    required this.resolveRedirectResult,
    required this.signInWithPopup,
    required this.signInWithRedirect,
    required this.signInWithCredential,
    required this.signOutFirebase,
    required this.initializeGoogleSignIn,
    required this.authenticateWithGoogle,
    required this.signOutGoogle,
  });

  factory AuthServiceDependencies.live({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  }) {
    return AuthServiceDependencies(
      authStateChanges: firebaseAuth.authStateChanges,
      currentUser: () => firebaseAuth.currentUser,
      resolveRedirectResult: () async {
        await firebaseAuth.getRedirectResult();
      },
      signInWithPopup: (provider) async {
        await firebaseAuth.signInWithPopup(provider);
      },
      signInWithRedirect: firebaseAuth.signInWithRedirect,
      signInWithCredential: (credential) async {
        await firebaseAuth.signInWithCredential(credential);
      },
      signOutFirebase: firebaseAuth.signOut,
      initializeGoogleSignIn: ({String? serverClientId}) async {
        await googleSignIn.initialize(serverClientId: serverClientId);
      },
      authenticateWithGoogle: () async {
        final account = await googleSignIn.authenticate();
        return GoogleAuthenticationTokens(
          idToken: account.authentication.idToken,
        );
      },
      signOutGoogle: googleSignIn.signOut,
    );
  }

  final AuthStateChangesCallback authStateChanges;
  final CurrentUserCallback currentUser;
  final ResolveRedirectResultCallback resolveRedirectResult;
  final PopupSignInCallback signInWithPopup;
  final RedirectSignInCallback signInWithRedirect;
  final SignInWithCredentialCallback signInWithCredential;
  final SignOutCallback signOutFirebase;
  final InitializeGoogleSignInCallback initializeGoogleSignIn;
  final AuthenticateWithGoogleCallback authenticateWithGoogle;
  final SignOutCallback signOutGoogle;
}

const String _serverClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

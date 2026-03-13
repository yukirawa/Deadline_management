import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kigenkanri/services/auth_service.dart';

void main() {
  group('AuthService.signInWithGoogle', () {
    test(
      'android uses google credentials flow and signs in with Firebase',
      () async {
        String? initializedServerClientId;
        AuthCredential? capturedCredential;
        var authenticateCalls = 0;

        final service = AuthService(
          isWeb: false,
          dependencies: AuthServiceDependencies(
            authStateChanges: () => const Stream<User?>.empty(),
            currentUser: () => null,
            resolveRedirectResult: () async {},
            signInWithPopup: (_) async {},
            signInWithRedirect: (_) async {},
            signInWithCredential: (credential) async {
              capturedCredential = credential;
            },
            signOutFirebase: () async {},
            initializeGoogleSignIn: ({String? serverClientId}) async {
              initializedServerClientId = serverClientId;
            },
            authenticateWithGoogle: () async {
              authenticateCalls += 1;
              return const GoogleAuthenticationTokens(idToken: 'test-id-token');
            },
            signOutGoogle: () async {},
          ),
        );

        await service.signInWithGoogle();

        expect(initializedServerClientId, isNull);
        expect(authenticateCalls, 1);
        expect(capturedCredential, isA<OAuthCredential>());
        final credential = capturedCredential! as OAuthCredential;
        expect(credential.providerId, 'google.com');
        expect(credential.signInMethod, 'google.com');
        expect(credential.idToken, 'test-id-token');
      },
    );

    test('android throws when Google ID token is missing', () async {
      final service = AuthService(
        isWeb: false,
        dependencies: AuthServiceDependencies(
          authStateChanges: () => const Stream<User?>.empty(),
          currentUser: () => null,
          resolveRedirectResult: () async {},
          signInWithPopup: (_) async {},
          signInWithRedirect: (_) async {},
          signInWithCredential: (_) async {},
          signOutFirebase: () async {},
          initializeGoogleSignIn: ({String? serverClientId}) async {},
          authenticateWithGoogle: () async =>
              const GoogleAuthenticationTokens(idToken: null),
          signOutGoogle: () async {},
        ),
      );

      await expectLater(service.signInWithGoogle(), throwsA(isA<StateError>()));
    });

    test('web falls back to redirect when popup sign-in is blocked', () async {
      var redirectCalls = 0;

      final service = AuthService(
        isWeb: true,
        dependencies: AuthServiceDependencies(
          authStateChanges: () => const Stream<User?>.empty(),
          currentUser: () => null,
          resolveRedirectResult: () async {},
          signInWithPopup: (_) async {
            throw FirebaseAuthException(code: 'popup-blocked');
          },
          signInWithRedirect: (_) async {
            redirectCalls += 1;
          },
          signInWithCredential: (_) async {},
          signOutFirebase: () async {},
          initializeGoogleSignIn: ({String? serverClientId}) async {},
          authenticateWithGoogle: () async =>
              const GoogleAuthenticationTokens(idToken: 'unused'),
          signOutGoogle: () async {},
        ),
      );

      await service.signInWithGoogle();

      expect(redirectCalls, 1);
    });
  });

  group('AuthService.describeSignInError', () {
    test('maps canceled account reauth failures to a configuration hint', () {
      final service = AuthService(
        isWeb: false,
        dependencies: AuthServiceDependencies(
          authStateChanges: () => const Stream<User?>.empty(),
          currentUser: () => null,
          resolveRedirectResult: () async {},
          signInWithPopup: (_) async {},
          signInWithRedirect: (_) async {},
          signInWithCredential: (_) async {},
          signOutFirebase: () async {},
          initializeGoogleSignIn: ({String? serverClientId}) async {},
          authenticateWithGoogle: () async =>
              const GoogleAuthenticationTokens(idToken: 'unused'),
          signOutGoogle: () async {},
        ),
      );

      final message = service.describeSignInError(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
          description: '[16] Account reauth failed.',
        ),
      );

      expect(message, contains('再認証'));
      expect(message, contains('設定'));
    });
  });
}

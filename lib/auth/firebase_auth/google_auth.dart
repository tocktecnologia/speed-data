import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

final _googleSignIn = GoogleSignIn(scopes: ['profile', 'email']);

class GoogleSignInAccountConflictException implements Exception {
  GoogleSignInAccountConflictException({
    required this.email,
    required this.pendingCredential,
  });

  final String email;
  final AuthCredential pendingCredential;
}

Future<UserCredential?> googleSignInFunc() async {
  try {
    if (kIsWeb) {
      // Once signed in, return the UserCredential
      return await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    }

    await signOutWithGoogle().catchError((_) => null);
    final auth = await (await _googleSignIn.signIn())?.authentication;
    if (auth == null) {
      return null;
    }
    final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken, accessToken: auth.accessToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  } on FirebaseAuthException catch (e) {
    final pending = e.credential;
    final email = (e.email ?? '').trim();
    if (e.code == 'account-exists-with-different-credential' &&
        pending != null &&
        email.isNotEmpty) {
      throw GoogleSignInAccountConflictException(
        email: email,
        pendingCredential: pending,
      );
    }
    rethrow;
  }
}

Future signOutWithGoogle() => _googleSignIn.signOut();

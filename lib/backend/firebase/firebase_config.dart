import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: "AIzaSyCJk4o-Yo6slHQ0S9QguDCbw06IUEW9Eb0",
            authDomain: "speed-data-tock.firebaseapp.com",
            projectId: "speed-data-tock",
            storageBucket: "speed-data-tock.firebasestorage.app",
            messagingSenderId: "26770981081",
            appId: "1:26770981081:web:1589b5d21c6b910a253ec8"));
  } else {
    await Firebase.initializeApp();
  }
}

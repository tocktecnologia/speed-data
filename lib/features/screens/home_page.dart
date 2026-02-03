import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/screens/admin/admin_dashboard.dart';
import 'package:speed_data/features/screens/pilot/pilot_dashboard.dart';

class SpeedDataHomePage extends StatefulWidget {
  const SpeedDataHomePage({Key? key}) : super(key: key);

  @override
  State<SpeedDataHomePage> createState() => _SpeedDataHomePageState();
}

class _SpeedDataHomePageState extends State<SpeedDataHomePage> {
  final FirestoreService _firestoreService = FirestoreService();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not Logged In')),
      );
    }

    return FutureBuilder<UserRole>(
      future: _firestoreService.getUserRole(user.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final role = snapshot.data ?? UserRole.unknown;

        if (role == UserRole.admin || role == UserRole.root) {
          return const AdminDashboard();
        } else if (role == UserRole.pilot) {
          return const PilotDashboard();
        } else {
          // If no role, maybe allow selection for now (Dev mode) or show error
          return _buildRoleSelector(user.uid);
        }
      },
    );
  }

  Widget _buildRoleSelector(String uid) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Role')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You do not have a role yet.'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await _firestoreService.setUserRole(uid, UserRole.pilot);
                setState(() {});
              },
              child: const Text('Join as Pilot'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await _firestoreService.setUserRole(uid, UserRole.admin);
                setState(() {});
              },
              child: const Text('Join as Admin'),
            ),
          ],
        ),
      ),
    );
  }
}

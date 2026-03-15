import '/auth/firebase_auth/auth_util.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'home_page_model.dart';
export 'home_page_model.dart';

import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:speed_data/features/screens/admin/event_list_screen.dart';
import 'package:speed_data/features/screens/pilot/pilot_dashboard.dart';
import 'package:speed_data/features/screens/team/team_dashboard_screen.dart';

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({super.key});

  static String routeName = 'HomePage';
  static String routePath = '/homePage';

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  late HomePageModel _model;
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _model = createModel(context, () => HomePageModel());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine the current user's role and route accordingly
    final user = currentUser; // From auth_util.dart (FlutterFlow)

    // If not logged in (should prevent reaching here via route guards, but safe check)
    if (!loggedIn) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return FutureBuilder<UserRole>(
      future: _firestoreService.getUserRole(user?.uid ?? ''),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final role = snapshot.data ?? UserRole.unknown;

        if (role == UserRole.admin || role == UserRole.root) {
          return const EventListScreen();
        } else if (role == UserRole.pilot) {
          return const PilotDashboard();
        } else if (role == UserRole.teamMember) {
          return const TeamDashboardScreen();
        } else {
          return _buildRoleSelector(context, user?.uid ?? '');
        }
      },
    );
  }

  Widget _buildRoleSelector(BuildContext context, String uid) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        title: const Text('Welcome to Speed Data'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              GoRouter.of(context).prepareAuthEvent();
              await authManager.signOut();
              GoRouter.of(context).clearRedirectLocation();
              if (context.mounted)
                context.goNamedAuth('Login', context.mounted);
            },
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Please select your role:',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _firestoreService.setUserRole(uid, UserRole.pilot);
                  setState(() {}); // Refresh to trigger PilotDashboard
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text('I am a PILOT'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _firestoreService.setUserRole(uid, UserRole.admin);
                  setState(() {}); // Refresh to trigger AdminDashboard
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text('I am an ADMIN'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _firestoreService.setUserRole(uid, UserRole.teamMember);
                  setState(() {});
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
              child: const Text('I am TEAM MEMBER'),
            ),
          ],
        ),
      ),
    );
  }
}

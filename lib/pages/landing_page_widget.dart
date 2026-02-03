import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/index.dart'; // To access Login/SignUp routes

class LandingPageWidget extends StatelessWidget {
  const LandingPageWidget({Key? key}) : super(key: key);

  static String routeName = 'LandingPage';
  static String routePath = '/landingPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme for "Speed Data"
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black, Color(0xFF1A1A1A)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.speed,
                color: Colors.white,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                'SPEED DATA',
                style: GoogleFonts.inter(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Select your role to continue',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 50),

              // Pilot Button
              _buildRoleButton(
                context,
                label: 'PILOT',
                icon: Icons.sports_motorsports,
                color: Colors.blueAccent,
                onPressed: () {
                  // Navigate to Login/Signup passing the role context
                  context.pushNamed(
                    SignUpWidget.routeName,
                    queryParameters: {'role': 'pilot'},
                  );
                },
              ),

              const SizedBox(height: 20),

              // Admin Button
              _buildRoleButton(
                context,
                label: 'ADMIN',
                icon: Icons.admin_panel_settings,
                color: Colors.redAccent,
                onPressed: () {
                  context.pushNamed(
                    SignUpWidget.routeName,
                    queryParameters: {'role': 'admin'},
                  );
                },
              ),

              const SizedBox(height: 40),
              TextButton(
                onPressed: () {
                  context.pushNamed(LoginWidget.routeName);
                },
                child: Text(
                  'Already have an account? Login',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 280,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.2),
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

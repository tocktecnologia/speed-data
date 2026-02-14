import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import '/flutter_flow/flutter_flow_util.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '/index.dart'; // To access Login/SignUp routes
import '../theme/speed_data_theme.dart';
import '../theme/speed_data_components.dart';

class LandingPageWidget extends StatelessWidget {
  const LandingPageWidget({Key? key}) : super(key: key);

  static String routeName = 'LandingPage';
  static String routePath = '/landingPage';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpeedDataTheme.bgBase,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: SpeedDataTheme.bgBase,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.speed,
                color: SpeedDataTheme.accentPrimary,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                'SPEED DATA',
                style: SpeedDataTheme.themeData.textTheme.displayMedium?.copyWith(
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select your role to continue',
                style: SpeedDataTheme.themeData.textTheme.bodyLarge?.copyWith(
                  color: SpeedDataTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 64),

              // Pilot Button
              SizedBox(
                width: 280,
                child: SpeedButton.primary(
                  text: 'PILOT',
                  icon: const Icon(Icons.sports_motorsports, size: 24),
                  onPressed: () {
                    context.pushNamed(
                      SignUpWidget.routeName,
                      queryParameters: {'role': 'pilot'},
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Admin Button
              SizedBox(
                width: 280,
                child: SpeedButton.secondary(
                  text: 'ADMIN',
                  icon: const Icon(Icons.admin_panel_settings, size: 24),
                  onPressed: () {
                    context.pushNamed(
                      SignUpWidget.routeName,
                      queryParameters: {'role': 'admin'},
                    );
                  },
                ),
              ),

              const SizedBox(height: 40),
              SpeedButton.ghost(
                text: 'Already have an account? Login',
                onPressed: () {
                  context.pushNamed(LoginWidget.routeName);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

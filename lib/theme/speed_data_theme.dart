import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SpeedDataTheme {
  // ---------------------------------------------------------------------------
  // Color Palette
  // ---------------------------------------------------------------------------

  // Background Hierarchy (Dark)
  static const Color bgBase = Color(0xFF0D0D0F);
  static const Color bgSurface = Color(0xFF161619);
  static const Color bgElevated = Color(0xFF1E1E22);
  static const Color bgOverlay = Color(0xFF26262B);

  // Text Hierarchy
  static const Color textPrimary = Color(0xFFF0F0F2);
  static const Color textSecondary = Color(0xFF9898A0);
  static const Color textDisabled = Color(0xFF4A4A52);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF2A2A30);
  static const Color borderDefault = Color(0xFF3A3A42);
  static const Color borderColor = borderDefault;
  static const Color borderFocus = accentPrimary;

  // Accent Colors
  static const Color accentPrimary = Color(0xFFFF1E00); // F1 Red
  static const Color accentSecondary = Color(0xFF8B5CF6);
  static const Color accentDanger = Color(0xFFEF4444);
  static final Color accentPrimaryMuted = const Color(0xFFFF1E00).withOpacity(0.15);

  // Semantic Colors (Motorsport)
  static const Color flagGreen = Color(0xFF22C55E);
  static const Color flagYellow = Color(0xFFEAB308);
  static const Color flagRed = Color(0xFFEF4444);
  static const Color flagBlue = Color(0xFF3B82F6);
  static const Color flagCheckered = Color(0xFFF0F0F2);

  // Data Visualization
  static const Color dataSpeed = Color(0xFF06B6D4);
  static const Color dataBest = Color(0xFFA855F7);
  static const Color dataCurrent = Color(0xFFF0F0F2);
  static const Color dataComparison = Color(0xFF6B7280);
  static const Color dataPositive = Color(0xFF22C55E);
  static const Color dataNegative = Color(0xFFEF4444);

  // Pilot Colors (21 distinct colors for map/leaderboard)
  static const List<Color> pilotColors = [
    Color(0xFFFF4500), // Red-Orange
    Color(0xFFFFFF00), // Yellow
    Color(0xFF00FF00), // Lime
    Color(0xFF00FFFF), // Cyan
    Color(0xFF0000FF), // Blue
    Color(0xFFFF00FF), // Magenta
    Color(0xFFFF007F), // Rose
    Color(0xFF7FFF00), // Chartreuse
    Color(0xFF00FF7F), // Spring Green
    Color(0xFF7F00FF), // Violet
    Color(0xFFFF7F00), // Orange
    Color(0xFF007FFF), // Azure
    Color(0xFFFF1493), // Deep Pink
    Color(0xFF32CD32), // Lime Green
    Color(0xFFFFD700), // Gold
    Color(0xFF1E90FF), // Dodger Blue
    Color(0xFF9932CC), // Dark Orchid
    Color(0xFFFF6347), // Tomato
    Color(0xFF40E0D0), // Turquoise
    Color(0xFFDA70D6), // Orchid
    Color(0xFFF0E68C), // Khaki
  ];

  // ---------------------------------------------------------------------------
  // Typography & Fonts
  // ---------------------------------------------------------------------------

  static TextTheme _textTheme = TextTheme(
    displayLarge: GoogleFonts.inter(
      fontSize: 40,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displayMedium: GoogleFonts.inter(
      fontSize: 32,
      fontWeight: FontWeight.bold,
      color: textPrimary,
    ),
    displaySmall: GoogleFonts.inter(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: textPrimary,
    ),
    headlineSmall: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: textPrimary,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: textPrimary,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: textPrimary,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: textSecondary,
    ),
  );

  static TextTheme get textTheme => _textTheme;

  // Monospace text styles helper
  static TextStyle get monoLg => GoogleFonts.jetBrainsMono(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    color: textPrimary,
    fontFeatures: [const FontFeature.tabularFigures()],
  );

  static TextStyle get monoMd => GoogleFonts.jetBrainsMono(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    fontFeatures: [const FontFeature.tabularFigures()],
  );

  static TextStyle get monoSm => GoogleFonts.jetBrainsMono(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    fontFeatures: [const FontFeature.tabularFigures()],
  );

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  // Radii
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusFull = 999.0;

  // Spacing
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // ---------------------------------------------------------------------------
  // Theme Data Builder
  // ---------------------------------------------------------------------------

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      
      // Colors
      scaffoldBackgroundColor: bgBase,
      colorScheme: const ColorScheme.dark(
        primary: accentPrimary,
        secondary: accentSecondary,
        surface: bgSurface,
        background: bgBase,
        error: flagRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: Colors.white,
      ),

      // Typography
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: _textTheme,
      
      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: bgBase,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: _textTheme.headlineLarge,
        iconTheme: const IconThemeData(color: textPrimary),
      ),

      // Card
      // Removed explicit CardTheme/CardThemeData assignment to use defaults and avoid type conflict
      // cardTheme: CardThemeData(...) or CardTheme(...) depending on version
      
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        fillColor: bgSurface,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: borderDefault, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: borderDefault, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: borderFocus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: flagRed, width: 1.5),
        ),
        labelStyle: _textTheme.bodyMedium?.copyWith(color: textSecondary),
        hintStyle: _textTheme.bodyMedium?.copyWith(color: textDisabled),
        helperStyle: _textTheme.bodySmall?.copyWith(color: textSecondary),
      ),

      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: _textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          minimumSize: const Size(0, 48), // Height 48dp
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: accentPrimary, width: 1.5),
          textStyle: _textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          minimumSize: const Size(0, 48),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentPrimary,
          textStyle: _textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          minimumSize: const Size(0, 40),
        ),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1,
        space: 1,
      ),

      // Tabs
      // Removed TabBarTheme assigment to avoid type conflict, will rely on default or component styling
      
      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentPrimary,
        foregroundColor: Colors.white,
        elevation: 4, // Slight elevation for FAB
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgSurface,
        modalBackgroundColor: bgSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
    );
  }
}

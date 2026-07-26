import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'design/pp.dart';

/// ThemeProvider manages dark/light mode state across the app.
///
/// Persists preference in SharedPreferences so the user's choice
/// survives app restarts. Uses ValueNotifier so any widget can
/// listen for theme changes without a full rebuild tree.
///
/// Usage:
///   ThemeProvider.instance.toggleDark();
///   ValueListenableBuilder(
///     valueListenable: ThemeProvider.instance,
///     builder: (ctx, isDark, _) => ...,
///   )
class ThemeProvider extends ValueNotifier<bool> {
  static final ThemeProvider instance = ThemeProvider._();
  static const _prefKey = 'dark_mode_enabled';

  ThemeProvider._() : super(false);

  /// Load persisted preference on app startup.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    instance.value = prefs.getBool(_prefKey) ?? false;
  }

  bool get isDark => value;

  Future<void> setDark(bool dark) async {
    value = dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, dark);
  }

  Future<void> toggleDark() => setDark(!value);

  // ── Light theme ─────────────────────────────────────────────────────────
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF9DC183),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF1F3F4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  // ── Dark theme ───────────────────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PP.obsidian,
        colorScheme: ColorScheme.dark(
          primary: PP.rose,
          secondary: PP.gold,
          surface: PP.cardDark,
          onSurface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: PP.obsidian,
          foregroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: PP.obsidian,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: PP.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: PP.r20,
          ),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
          displayLarge: GoogleFonts.playfairDisplay(color: Colors.white),
        ),
      );
}

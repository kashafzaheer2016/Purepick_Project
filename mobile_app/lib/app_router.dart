import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/result_screen.dart';
import 'screens/barcode_scanner_screen.dart';
import 'screens/history_screen.dart';
import 'screens/saved_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/ai_tips_screen.dart';
import 'screens/skin_analysis_screen.dart';
import 'screens/skin_result_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/privacy_screen.dart';

/// PurePick named route registry.
///
/// Batch 6: Replaces ad-hoc Navigator.push() calls throughout the app
/// with declared named routes. Benefits:
///   - Deep linking support (e.g. purepick://reset-password?token=xxx)
///   - Testable navigation (verify route names in widget tests)
///   - Single source of truth for route names
///   - onGenerateRoute handles argument passing cleanly
class AppRouter {
  // ── Route name constants ──────────────────────────────────────────────────
  static const String welcome        = '/';
  static const String login          = '/login';
  static const String signup         = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword  = '/reset-password';   // deep link target
  static const String main           = '/main';
  static const String home           = '/home';
  static const String scan           = '/scan';
  static const String analysis       = '/analysis';
  static const String result         = '/result';
  static const String barcodeScanner = '/barcode';
  static const String history        = '/history';
  static const String saved          = '/saved';
  static const String aiChat         = '/ai-chat';
  static const String aiTips         = '/ai-tips';
  static const String skinAnalysis   = '/skin-analysis';
  static const String skinResult     = '/skin-result';
  static const String profileSetup   = '/profile-setup';
  static const String settings       = '/settings';
  static const String privacy        = '/privacy';

  /// Route generator — called for every named navigation.
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case welcome:
        return _slide(const WelcomeScreen());

      case login:
        return _fade(const LoginScreen());

      case signup:
        return _slide(const SignupScreen());

      case forgotPassword:
      case resetPassword:
        // Deep link: /reset-password?token=xxx passes token as arg
        final token = (settings.arguments as Map<String, String>?)?['token'];
        return _slide(ForgotPasswordScreen(prefillToken: token));

      case main:
        return _fade(const MainScreen());

      case home:
        return _fade(const HomeScreen());

      case scan:
        return _slide(const ScannerScreen());

      case barcodeScanner:
        return _slide(const BarcodeScannerScreen());

      case analysis:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return _fade(AnalysisScreen(imagePath: args['imagePath'] ?? ''));

      case result:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return _slide(ResultScreen(
          score:            (args['score'] as num?)?.toDouble() ?? 0,
          riskLevel:        args['riskLevel'] as String? ?? 'Safe',
          dangerItems:      (args['dangerItems'] as List?)?.cast<Map<String, dynamic>>() ?? [],
          aiInsight:        args['aiInsight'] as String? ?? '',
          personalWarnings: args['personalWarnings'] as String? ?? '',
          productName:      args['productName'] as String?,
          brandName:        args['brandName'] as String?,
          imageUrl:         args['imageUrl'] as String?,
          lookupSource:     args['lookupSource'] as String?,
        ));

      case history:
        return _slide(const HistoryScreen());

      case saved:
        return _slide(const SavedScreen());

      case aiChat:
        return _slide(const AiChatScreen());

      case aiTips:
        return _slide(const AiTipsScreen());

      case skinAnalysis:
        return _slide(const SkinAnalysisScreen());

      case skinResult:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return _premiumFade(SkinResultScreen(result: args));

      case profileSetup:
        return _slide(const ProfileSetupScreen());

      case AppRouter.settings:
        return _slide(const SettingsScreen());

      case privacy:
        return _slide(const PrivacyScreen());

      default:
        return _fade(const WelcomeScreen());
    }
  }

  // ── Transition helpers ────────────────────────────────────────────────────

  static PageRoute _slide(Widget page) => PageRouteBuilder(
        settings: RouteSettings(name: page.runtimeType.toString()),
        pageBuilder: (_, a, __) => page,
        transitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );

  static PageRoute _fade(Widget page) => PageRouteBuilder(
        settings: RouteSettings(name: page.runtimeType.toString()),
        pageBuilder: (_, a, __) => page,
        transitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      );

  static PageRoute _premiumFade(Widget page) => PageRouteBuilder(
        settings: RouteSettings(name: page.runtimeType.toString()),
        pageBuilder: (_, a, __) => page,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.07), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
            child: child,
          ),
        ),
      );
}

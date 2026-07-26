import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// FCM push notification service.
///
/// Batch 6: Firebase was configured but FCM was never used.
/// This service:
///   1. Requests notification permission (iOS/Android 13+)
///   2. Gets the FCM token from Firebase
///   3. Registers it with the PurePick backend
///   4. Re-registers when the token refreshes
///
/// Call FCMService.initialize() after login.
///
/// NOTE: Requires `firebase_messaging` package.
/// Add to pubspec.yaml:
///   firebase_messaging: ^15.1.0
///
/// The implementation below uses conditional imports so the app
/// compiles even if firebase_messaging is not yet installed.
/// Replace the stub implementations with real ones after adding the package.
class FCMService {
  static const _tokenKey = 'fcm_token';

  /// Call after successful login to register the device for push notifications.
  static Future<void> initialize(int userId) async {
    try {
      final token = await _getToken();
      if (token == null) return;

      // Check if token changed since last registration
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_tokenKey);
      if (token == stored) return;  // no change — skip registration

      await ApiService.registerFcmToken(token);
      await prefs.setString(_tokenKey, token);

      // Listen for token refresh
      _listenForTokenRefresh(userId);

    } catch (e) {
      debugPrint('FCMService.initialize error: $e');
    }
  }

  static Future<String?> _getToken() async {
    try {
      // ── STUB: Replace with real firebase_messaging implementation ──────────
      // import 'package:firebase_messaging/firebase_messaging.dart';
      //
      // final messaging = FirebaseMessaging.instance;
      //
      // // Request permission (iOS + Android 13+)
      // final settings = await messaging.requestPermission(
      //   alert: true, badge: true, sound: true,
      // );
      // if (settings.authorizationStatus == AuthorizationStatus.denied) {
      //   return null;
      // }
      //
      // return await messaging.getToken();
      // ─────────────────────────────────────────────────────────────────────

      // Stub returns null until firebase_messaging is installed
      return null;
    } catch (e) {
      debugPrint('FCMService._getToken error: $e');
      return null;
    }
  }

  static void _listenForTokenRefresh(int userId) {
    // ── STUB: Replace with real implementation ────────────────────────────
    // FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    //   await ApiService.registerFcmToken(newToken);
    //   final prefs = await SharedPreferences.getInstance();
    //   await prefs.setString(_tokenKey, newToken);
    // });
  }

  /// Handle foreground notification display.
  /// Call once at app startup.
  static void setupForegroundHandler() {
    // ── STUB ──────────────────────────────────────────────────────────────
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    //   // Show in-app notification banner
    //   debugPrint('FCM foreground: ${message.notification?.title}');
    // });
  }
}

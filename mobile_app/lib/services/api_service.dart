import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// PurePick API Service
///
/// Changes vs original:
///   ✓ Base URL is configurable — no hardcoded LAN IP
///   ✓ All requests attach Bearer JWT from SharedPreferences
///   ✓ user_id no longer passed in request bodies (comes from token)
///   ✓ Token refresh logic on 401 with single retry
///   ✓ Logout clears stored tokens
class ApiService {
  // WHY: Use env-configurable URL. For local dev, override in app config.
  // Release builds should point to your deployed server.
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://purepick-production.up.railway.app/api',
  );

  static String get baseUrl => _defaultBaseUrl;

  // ── Token management ────────────────────────────────────────────────────

  static Future<String?> _getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<String?> _getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  static Future<void> _saveTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);
  }

  static Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('user_name');
  }

  /// Returns auth headers with Bearer token.
  /// Throws [SessionExpiredException] if no token found.
  static Future<Map<String, String>> authHeaders() async {
    final token = await _getAccessToken();
    if (token == null) throw SessionExpiredException();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns the new access token, or throws [SessionExpiredException].
  static Future<String> _refreshAccessToken() async {
    final refreshToken = await _getRefreshToken();
    if (refreshToken == null) throw SessionExpiredException();

    final response = await http.post(
      Uri.parse('$baseUrl/token/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'refresh': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final newAccess = data['access'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', newAccess);
      return newAccess;
    }

    // Refresh token also expired — user must log in again
    await _clearSession();
    throw SessionExpiredException();
  }

  /// Makes an authenticated request with automatic token refresh on 401.
  static Future<http.Response> authenticatedRequest(
    Future<http.Response> Function(Map<String, String> headers) requestFn,
  ) async {
    var headers = await authHeaders();
    var response = await requestFn(headers);

    // WHY: On 401, try refreshing once before giving up
    if (response.statusCode == 401) {
      await _refreshAccessToken();
      headers = await authHeaders();
      response = await requestFn(headers);
    }

    return response;
  }

  // ── Auth ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register(
    String name,
    String username,
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/register/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'name': name, 'username': username, 'email': email, 'password': password}),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      await _saveTokens(data['access'], data['refresh']);
      await _persistUserLocally(data);
      return data;
    }
    throw ApiException(json.decode(response.body)['error'] ?? 'Registration failed');
  }

  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      await _saveTokens(data['access'], data['refresh']);
      await _persistUserLocally(data);
      return data;
    }
    throw ApiException(json.decode(response.body)['error'] ?? 'Login failed');
  }

  static Future<Map<String, dynamic>> loginWithGoogle(String? token) async {
    if (token == null) throw ApiException('Google token is null');

    final response = await http
        .post(
          Uri.parse('$baseUrl/google-login/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'token': token}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      await _saveTokens(data['access'], data['refresh']);
      await _persistUserLocally(data);
      return data; // includes is_new_user flag
    }
    throw ApiException(
        json.decode(response.body)['error'] ?? 'Google login failed');
  }

  static Future<void> deleteAccount() async {
    final headers = await authHeaders();
    final response = await http
        .delete(Uri.parse('$baseUrl/delete-account/'), headers: headers)
        .timeout(const Duration(seconds: 60));
    await _clearSession();
    if (response.statusCode != 200) {
      throw ApiException('Failed to delete account. Please try again.');
    }
  }

  static Future<void> logout() async {
    try {
      final refreshToken = await _getRefreshToken();
      if (refreshToken != null) {
        final headers = await authHeaders();
        await http.post(
          Uri.parse('$baseUrl/logout/'),
          headers: headers,
          body: json.encode({'refresh': refreshToken}),
        );
      }
    } catch (_) {
      // Always clear local session even if server call fails
    } finally {
      await _clearSession();
    }
  }

  static Future<void> _persistUserLocally(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    if (data['user_id'] != null) await prefs.setInt('user_id', data['user_id']);
    if (data['name'] != null) await prefs.setString('user_name', data['name']);
    if (data['username'] != null) await prefs.setString('username', data['username']);
    if (data['gender'] != null) await prefs.setString('user_gender', data['gender']);
    if (data['skin_type'] != null) await prefs.setString('user_skin_type', data['skin_type']);
  }

  // ── Profile ─────────────────────────────────────────────────────────────

  static Future<void> updateProfile(
    int userId,
    String allergies, {
    String skinType = 'Normal',
    String gender = 'Other',
    String skinConditions = '',
    String customAllergens = '',
    int? age,
  }) async {
    final body = <String, dynamic>{
      'allergies': allergies,
      'skin_type': skinType,
      'gender': gender,
      'skin_conditions': skinConditions,
      'custom_allergens': customAllergens,
    };
    if (age != null) body['age'] = age;

    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/profile/update/'),
        headers: headers,
        body: json.encode(body),
      ),
    );

    if (response.statusCode != 200) {
      throw ApiException('Failed to save profile');
    }
  }

  static Future<Map<String, dynamic>> getProfile(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(
        Uri.parse('$baseUrl/profile/$userId/'),
        headers: headers,
      ),
    );

    if (response.statusCode == 200) return json.decode(response.body);
    throw ApiException('Failed to load profile');
  }

  // ── AI Analysis ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> analyzeIngredients(
    List<String> ingredients,
    int userId,  // kept for API compatibility, not sent to server
  ) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/analyze/'),
        headers: headers,
        body: json.encode({'ingredients': ingredients}),
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 202) return json.decode(response.body);
    throw ApiException('Analysis failed: ${response.statusCode}');
  }

  static Future<Map<String, dynamic>> analyzeLabelImage(
    String imagePath,
    int userId,  // kept for API compatibility, not sent to server
  ) async {
    final token = await _getAccessToken();
    if (token == null) throw SessionExpiredException();

    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/scan-label/'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('image', imagePath));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200 || response.statusCode == 202) return json.decode(response.body);
    throw ApiException('Image analysis failed: ${response.body}');
  }

  // ── History & Saved ──────────────────────────────────────────────────────

  static Future<List<dynamic>> getHistory(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(Uri.parse('$baseUrl/history/$userId/'), headers: headers)
          .timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw ApiException('Failed to load history');
  }

  static Future<void> saveProduct({
    required int userId,
    required String name,
    required int score,
    String? brand,
    String? ingredients,
    String? riskLevel,
  }) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/saved/add/'),
        headers: headers,
        body: json.encode({
          'name': name,
          'score': score,
          'brand': brand,
          'ingredients': ingredients,
          'risk_level': riskLevel,
        }),
      ),
    );
    if (response.statusCode != 200) throw ApiException('Failed to save product');
  }

  static Future<List<dynamic>> getSavedProducts(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(Uri.parse('$baseUrl/saved/$userId/'), headers: headers),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw ApiException('Failed to load saved products');
  }

  static Future<void> deleteSavedProduct(int productId) async {
    final response = await authenticatedRequest(
      (headers) => http.delete(
        Uri.parse('$baseUrl/saved/delete/$productId/'),
        headers: headers,
      ),
    );
    if (response.statusCode != 200) throw ApiException('Failed to delete product');
  }

  // ── AI Chat & Tips ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> chatWithAI(
    String query,
    int userId, {
    List<Map<String, String>> history = const [],
  }) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/chat/'),
        headers: headers,
        body: json.encode({'query': query, 'history': history}),
      ),
    );
    if (response.statusCode == 200 || response.statusCode == 202) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Chat failed');
  }

  static Future<Map<String, dynamic>> getAiTips(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(Uri.parse('$baseUrl/ai-tips/$userId/'), headers: headers),
    );
    // Returns { task_id, status: PENDING } — caller must poll
    if (response.statusCode == 200 || response.statusCode == 202) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    return {};
  }

  static Future<Map<String, dynamic>> getHomeStats(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(Uri.parse('$baseUrl/home-stats/$userId/'), headers: headers),
    );
    if (response.statusCode == 200) return json.decode(response.body);
    throw ApiException('Failed to load home stats');
  }

  static Future<List<dynamic>> getAlternatives({String category = ''}) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/alternatives/'),
        headers: headers,
        body: json.encode({'category': category}),
      ),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body)['alternatives'] ?? [];
    }
    return [];
  }

  // ── Skin Analysis ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> analyzeFace(String imagePath, int userId) async {
    final token = await _getAccessToken();
    if (token == null) throw SessionExpiredException();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/skin/analyze-face/'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('image', imagePath));

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final body = json.decode(response.body) as Map<String, dynamic>;

    if (response.statusCode == 200 || response.statusCode == 202) return body;
    throw ApiException('Skin analysis request failed: ${response.statusCode}');
  }

  static Future<List<dynamic>> getSkinHistory(int userId) async {
    final response = await authenticatedRequest(
      (headers) => http.get(Uri.parse('$baseUrl/skin/history/$userId/'), headers: headers)
          .timeout(const Duration(seconds: 60)),
    );
    if (response.statusCode == 200) return json.decode(response.body) as List;
    throw ApiException('Failed to load skin history');
  }

  // ── Password Reset ──────────────────────────────────────────────────────────

  /// Step 1: Request a password reset token be sent to the user's email.
  /// Always succeeds (server never reveals if account exists).
  static Future<void> requestPasswordReset(String usernameOrEmail) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/password-reset/request/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'username_or_email': usernameOrEmail}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw ApiException('Request failed');
    }
  }

  /// Step 2: Confirm reset with token + new password.
  static Future<void> confirmPasswordReset(String token, String newPassword) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/password-reset/confirm/'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'token': token, 'new_password': newPassword}),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) return;
    final body = json.decode(response.body);
    throw ApiException(body['error'] as String? ?? 'Reset failed');
  }

  // ── Barcode Lookup ───────────────────────────────────────────────────────────

  /// Enqueues a barcode → Open Beauty Facts → analysis task.
  /// Returns { task_id, status } — poll /api/task/<task_id>/ for result.
  static Future<Map<String, dynamic>> barcodeAnalysis(
    String barcode,
    int userId,
  ) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/barcode-lookup/'),
        headers: headers,
        body: json.encode({'barcode': barcode}),
      ),
    );

    if (response.statusCode == 200 || response.statusCode == 202) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Barcode lookup failed: ${response.statusCode}');
  }

  // ── Notifications ────────────────────────────────────────────────────────────

  /// Register device FCM token for push notifications.
  static Future<void> registerFcmToken(String fcmToken) async {
    final response = await authenticatedRequest(
      (headers) => http.post(
        Uri.parse('$baseUrl/notifications/register-token/'),
        headers: headers,
        body: json.encode({'fcm_token': fcmToken}),
      ),
    );
    if (response.statusCode != 200) {
      throw ApiException('Failed to register notification token');
    }
  }
}

// ── Exception types ─────────────────────────────────────────────────────────

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class SessionExpiredException implements Exception {
  const SessionExpiredException();
  @override
  String toString() => 'Session expired. Please log in again.';
}

class SkinAnalysisApiException implements Exception {
  final String message;
  const SkinAnalysisApiException(this.message);
  @override
  String toString() => message;
}

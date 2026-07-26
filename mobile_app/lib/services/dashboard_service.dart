import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class DashboardData {
  final Map<String, dynamic> weather;
  final Map<String, String> skinCast;
  final Map<String, dynamic>? todayLog;

  DashboardData({required this.weather, required this.skinCast, this.todayLog});

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      weather: json['weather'],
      skinCast: Map<String, String>.from(json['skin_cast']),
      todayLog: json['today_log'],
    );
  }
}

class DashboardService {
  /// Fetches unified weather, AQI, and advice based on location.
  static Future<DashboardData> getDashboard(double lat, double lon) async {
    final headers = await ApiService.authHeaders();
    final url = Uri.parse('${ApiService.baseUrl}/dashboard/?lat=$lat&lon=$lon');
    
    final response = await http.get(url, headers: headers);
    if (response.statusCode == 200) {
      return DashboardData.fromJson(json.decode(response.body));
    }
    throw Exception('Failed to load dashboard data');
  }

  /// Saves today's skin diary entry.
  static Future<bool> saveSkinLog({
    required int score,
    required List<String> tags,
    required bool am,
    required bool pm,
  }) async {
    final response = await ApiService.authenticatedRequest(
      (headers) => http.post(
        Uri.parse('${ApiService.baseUrl}/log-skin/'),
        headers: headers,
        body: json.encode({
          'score': score,
          'tags': tags,
          'am': am,
          'pm': pm,
        }),
      ),
    );
    return response.statusCode == 200;
  }
}

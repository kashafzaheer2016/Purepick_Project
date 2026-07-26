import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'package:http/http.dart' as http;

class SkinCastData {
  final double temp;
  final int humidity;
  final double uv;
  final int aqi;
  final String city;

  SkinCastData({required this.temp, required this.humidity, required this.uv, required this.aqi, required this.city});

  factory SkinCastData.fromJson(Map<String, dynamic> json) => SkinCastData(
    temp: (json['temp'] as num).toDouble(),
    humidity: (json['humidity'] as num).toInt(),
    uv: (json['uv'] as num).toDouble(),
    aqi: (json['aqi'] as num).toInt(),
    city: json['city'] ?? 'Local Cast',
  );
}

class SkinCastResult {
  final String title;
  final String message;
  final String iconName;
  final List<int> themeColors;

  SkinCastResult({required this.title, required this.message, required this.iconName, required this.themeColors});
}

class SkinCastService {
  static Future<SkinCastData> fetchData() async {
    try {
      // 1. Get Precise Location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services disabled');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permission denied');
      }
      
      // Use High Accuracy for precise city detection
      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      debugPrint("SkinCast: Coordinates found: ${pos.latitude}, ${pos.longitude}");

      // 2. Fetch from Backend
      final headers = await ApiService.authHeaders();
      final url = Uri.parse('${ApiService.baseUrl}/skincast/?lat=${pos.latitude}&lon=${pos.longitude}');
      final resp = await http.get(url, headers: headers);

      if (resp.statusCode == 200) {
        return SkinCastData.fromJson(json.decode(resp.body));
      }
      throw Exception('Failed to load weather data');
    } catch (e) {
      debugPrint("SkinCast fetch error: $e");
      // Fallback Mock Data as per requirements
      return SkinCastData(temp: 22.0, humidity: 45, uv: 2.0, aqi: 30, city: 'PurePick HQ');
    }
  }

  static SkinCastResult getRecommendation(SkinCastData data, String skinType) {
    final now  = DateTime.now().hour;
    final type = skinType.toLowerCase();
    final isDaytime = now >= 6 && now < 19;

    // ── Rule 1: Night Repair (7pm–5am) ──────────────────────────────────────
    if (now >= 19 || now < 5) {
      return SkinCastResult(
        title: "Night Repair Mode",
        message: "Time to repair. Apply Retinol or Peptides, seal with night cream.",
        iconName: "moon",
        themeColors: [0xFF0D0B0C, 0xFF2D1B22],
      );
    }

    // ── Rule 2: Extreme Heat — any skin type (temp ≥ 38°C) ──────────────────
    if (data.temp >= 38) {
      return SkinCastResult(
        title: "Extreme Heat Alert",
        message: "Very high temperature. Apply SPF 50+, use a light gel moisturiser, and carry facial mist.",
        iconName: "flame",
        themeColors: [0xFFD32F2F, 0xFFB71C1C],
      );
    }

    // ── Rule 3: High UV Index (≥ 6) during daytime ──────────────────────────
    if (isDaytime && data.uv >= 6) {
      final spfTip = type == 'oily'
          ? 'Use a matte SPF 50+ sunscreen — reapply every 2 hours.'
          : type == 'sensitive'
          ? 'Use a mineral SPF 50+ (zinc oxide). Avoid chemical filters.'
          : 'Apply broad-spectrum SPF 50+ immediately. Seek shade 10am–2pm.';
      return SkinCastResult(
        title: "High UV — Sunscreen Needed",
        message: "UV Index ${data.uv.toStringAsFixed(1)} is dangerous. $spfTip",
        iconName: "sun",
        themeColors: [0xFFFF8F00, 0xFFE65100],
      );
    }

    // ── Rule 4: Moderate UV — apply sunscreen reminder (UV 3–5) ─────────────
    if (isDaytime && data.uv >= 3) {
      return SkinCastResult(
        title: "Apply Sunscreen",
        message: "UV Index ${data.uv.toStringAsFixed(1)} — moderate exposure. Apply SPF 30+ before going outside.",
        iconName: "sun",
        themeColors: [0xFFFFA726, 0xFFE65100],
      );
    }

    // ── Rule 5: Hot & Humid — Sweat Alert (any skin type) ───────────────────
    if (data.temp >= 33 && data.humidity >= 55) {
      final msg = type == 'oily' || type == 'combination'
          ? 'High heat and humidity. Use oil-free gel moisturiser and blotting sheets.'
          : 'High heat and humidity. Use a lightweight water-based moisturiser.';
      return SkinCastResult(
        title: "Sweat Alert",
        message: msg,
        iconName: "flame",
        themeColors: [0xFFF44336, 0xFFB71C1C],
      );
    }

    // ── Rule 6: High Pollution ───────────────────────────────────────────────
    if (data.aqi > 150) {
      return SkinCastResult(
        title: "High Pollution",
        message: "Poor air quality. Apply Vitamin C serum to neutralise free radicals. Double cleanse tonight.",
        iconName: "alert",
        themeColors: [0xFF616161, 0xFF212121],
      );
    }

    // ── Rule 7: Hot Dry Day ──────────────────────────────────────────────────
    if (data.temp >= 30 && data.humidity < 35) {
      return SkinCastResult(
        title: "Hot & Dry — Hydrate",
        message: "Low humidity. Apply Hyaluronic Acid on damp skin and seal with moisturiser. Drink extra water.",
        iconName: "flame",
        themeColors: [0xFFFF7043, 0xFFBF360C],
      );
    }

    // ── Rule 8: Cold Dry — Winter ────────────────────────────────────────────
    if (data.temp < 15 && data.humidity < 35) {
      return SkinCastResult(
        title: "Winter Dry Skin",
        message: "Cold, dry air. Lock in hydration with a ceramide-rich balm. Use gentle cleanser.",
        iconName: "snowflake",
        themeColors: [0xFF0288D1, 0xFF01579B],
      );
    }

    // ── Rule 9: Warm & Humid — Breakout Risk ────────────────────────────────
    if (data.temp >= 28 && data.humidity >= 70 &&
        (type == 'oily' || type == 'combination' || type == 'acne-prone')) {
      return SkinCastResult(
        title: "Breakout Risk",
        message: "Warm and humid — higher chance of congestion. Use salicylic acid cleanser and skip heavy creams.",
        iconName: "alert",
        themeColors: [0xFF7B1FA2, 0xFF4A148C],
      );
    }

    // ── DEFAULT: All Clear ───────────────────────────────────────────────────
    return SkinCastResult(
      title: "All Clear",
      message: "Good conditions for your skin today. ${isDaytime ? 'Still apply SPF 30 as daily protection.' : 'Follow your evening routine.'}",
      iconName: "check",
      themeColors: [0xFF388E3C, 0xFF1B5E20],
    );
  }
}

import 'package:flutter/material.dart';

class UserProfile {
  final int id;
  final String name;
  final String email;
  final List<String> allergies;
  final List<String> conditions;
  final String skinType;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.allergies = const [],
    this.conditions = const [],
    this.skinType = "Normal",
  });

  UserProfile copyWith({
    int? id,
    String? name,
    String? email,
    List<String>? allergies,
    List<String>? conditions,
    String? skinType,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      allergies: allergies ?? this.allergies,
      conditions: conditions ?? this.conditions,
      skinType: skinType ?? this.skinType,
    );
  }
}

class GlobalState extends ValueNotifier<UserProfile?> {
  // Singleton pattern
  static final GlobalState _instance = GlobalState._internal();
  factory GlobalState() => _instance;

  GlobalState._internal() : super(null);

  void setUser(int id, String name, String email) {
    value = UserProfile(id: id, name: name, email: email);
  }

  void updateProfile(
    List<String> allergies,
    List<String> conditions,
    String skinType,
  ) {
    if (value != null) {
      value = value!.copyWith(
        allergies: allergies,
        conditions: conditions,
        skinType: skinType,
      );
    }
  }

  void logout() {
    value = null;
  }
}

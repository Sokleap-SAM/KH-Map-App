import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

class AuthService {
  static const String baseUrl = "http://10.0.2.2:3000";
  static const String _tokenKey = 'access_token';

  // Broadcasts the current access token. Listeners (e.g. MapScreen) react
  // to login/logout so they can refresh per-user state like favorites.
  static final ValueNotifier<String?> tokenNotifier = ValueNotifier<String?>(
    null,
  );

  // Call once during app startup so the notifier reflects any persisted token.
  static Future<void> initTokenNotifier() async {
    final prefs = await SharedPreferences.getInstance();
    tokenNotifier.value = prefs.getString(_tokenKey);
  }
  static const String baseUrl = AppConfig.baseUrl;

  // 1. REGISTER
  Future<http.Response> register(
    String name,
    String email,
    String password,
  ) async {
    final url = Uri.parse("$baseUrl/users/register");
    return await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"name": name, "email": email, "password": password}),
    );
  }

  // 2. LOGIN
  Future<bool> login(String email, String password) async {
    final url = Uri.parse("$baseUrl/users/login");
    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Save JWT Token to phone memory
      final prefs = await SharedPreferences.getInstance();
      final token = data['access_token'] as String?;
      await prefs.setString(_tokenKey, token ?? '');
      tokenNotifier.value = token;
      return true;
    }
    return false;
  }

  // 3. LOGOUT
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    tokenNotifier.value = null;
  }

  Future<bool> sendForgotPasswordOtp(String email) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/forgot-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"email": email}),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }

  Future<bool> resetPassword(
    String email,
    String otp,
    String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse("$baseUrl/users/reset-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "otp": otp,
        "newPassword": newPassword,
      }),
    );
    return response.statusCode == 201 || response.statusCode == 200;
  }
}

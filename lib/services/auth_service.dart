import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "http://localhost:3000";

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
      await prefs.setString('access_token', data['access_token']);
      return true;
    }
    return false;
  }

  // 3. LOGOUT
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
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

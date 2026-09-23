import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';

/// Typed failure carrying the backend's message so the UI can show why an edit
/// was rejected (wrong current password, email already taken, …). Mirrors
/// AdminApiException / DriverApiException.
class ProfileApiException implements Exception {
  final int statusCode;
  final String message;
  ProfileApiException(this.statusCode, this.message);

  /// The backend rejects a bad `currentPassword` with 401. Distinguished so the
  /// UI can attach the error to that field instead of showing a generic banner.
  bool get isWrongPassword => statusCode == 401;

  @override
  String toString() => 'ProfileApiException($statusCode): $message';
}

/// Self-service account endpoints — what a signed-in user may read and change
/// about their own account, regardless of role.
///
/// Deliberately separate from [AdminService]: the backend's self-service DTO is
/// much narrower (no role, status, isVerified or email), and a password change
/// here requires proving the current one.
class ProfileService {
  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';

  static const String _tokenKey = 'access_token';

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<Map<String, String>> _authHeaders({bool json = false}) async {
    final token = await _token();
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  String _extractMessage(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['message'] != null) {
        final m = body['message'];
        return m is List ? m.join(', ') : m.toString();
      }
    } catch (_) {}
    return r.body.isNotEmpty ? r.body : 'HTTP ${r.statusCode}';
  }

  Never _throwFor(http.Response r) =>
      throw ProfileApiException(r.statusCode, _extractMessage(r));

  /// GET /users/profile — the signed-in user's own account.
  Future<AppUser> fetchProfile() async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/users/profile'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    return AppUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// PATCH /users/me — change your own name and/or password.
  ///
  /// [currentPassword] is required by the backend whenever [newPassword] is
  /// present; sending a new password without it is rejected. Passing neither
  /// password is a name-only edit.
  Future<AppUser> updateProfile({
    String? name,
    String? currentPassword,
    String? newPassword,
  }) async {
    final body = <String, dynamic>{
      if (name != null && name.isNotEmpty) 'name': name,
      if (newPassword != null && newPassword.isNotEmpty) ...{
        'currentPassword': currentPassword ?? '',
        'newPassword': newPassword,
      },
    };
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/users/me'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
    return AppUser.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }
}

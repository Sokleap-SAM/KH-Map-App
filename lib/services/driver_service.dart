import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_mqtt_credentials.dart';
import '../models/driver_profile.dart';
import '../models/trip.dart';

/// Typed exception carrying the backend's machine-readable message so the UI
/// can branch on it (per "Error handling cheat sheet" in driver-frontend-brief.md).
class DriverApiException implements Exception {
  final int statusCode;
  final String message;
  DriverApiException(this.statusCode, this.message);
  @override
  String toString() => 'DriverApiException($statusCode): $message';
}

class DriverService {
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

  Never _throwFor(http.Response r) {
    final path = r.request?.url.path ?? '';
    throw DriverApiException(r.statusCode, '${_extractMessage(r)} ($path)');
  }

  /// GET /drivers/me — driver profile incl. live `assignedBus` (admin can
  /// reassign without the driver re-logging, so we must fetch this rather
  /// than trust the JWT).
  Future<DriverProfile> fetchProfile() async {
    final r = await http
        .get(Uri.parse('$_baseUrl/drivers/me'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    return DriverProfile.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// PATCH /drivers/me/status — `status` is "on" or "off".
  /// Returns the new server-side status.
  Future<String> setShiftStatus(String status) async {
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/drivers/me/status'),
          headers: await _authHeaders(json: true),
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
    final body = jsonDecode(r.body);
    if (body is Map && body['status'] is String) return body['status'] as String;
    return status;
  }

  /// GET /drivers/me/mqtt-credentials — password rotates per call.
  Future<DriverMqttCredentials> fetchMqttCredentials() async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/drivers/me/mqtt-credentials'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    return DriverMqttCredentials.fromJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
  }

  Future<Trip> startTrip(String tripId) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/drivers/me/trips/start'),
          headers: await _authHeaders(json: true),
          body: jsonEncode({'tripId': tripId}),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
    return Trip.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// Idempotent — returns `{cancelled: bool, tripId?}`.
  Future<bool> cancelCurrentTrip() async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/drivers/me/trips/cancel'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
    final body = jsonDecode(r.body);
    if (body is Map && body['cancelled'] is bool) return body['cancelled'] as bool;
    return false;
  }

  /// GET /drivers/me/trips — server-side filtered to the driver's bus and
  /// pre-split into today/history. No client-side filtering needed.
  Future<DriverTrips> fetchMyTrips() async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/drivers/me/trips'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    List<Trip> parse(String key) => (body[key] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Trip.fromJson)
        .toList();
    return DriverTrips(
      assignedBusId: body['assignedBusId'] as String?,
      today: parse('today'),
      history: parse('history'),
    );
  }
}

/// Result of `GET /drivers/me/trips`.
class DriverTrips {
  final String? assignedBusId;
  final List<Trip> today;
  final List<Trip> history;

  const DriverTrips({
    required this.assignedBusId,
    required this.today,
    required this.history,
  });

  List<Trip> get all => [...today, ...history];
}

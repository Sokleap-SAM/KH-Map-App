import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';

class SearchHistoryEntry {
  final String id;
  final String name;
  final String categoryName;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const SearchHistoryEntry({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory SearchHistoryEntry.fromPlace(Place p) => SearchHistoryEntry(
        id: p.id,
        name: p.name,
        categoryName: p.category?.name ?? 'Place',
        latitude: p.latitude,
        longitude: p.longitude,
        timestamp: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'categoryName': categoryName,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toIso8601String(),
      };

  factory SearchHistoryEntry.fromJson(Map<String, dynamic> json) {
    final rawId = (json['placeId'] ?? json['id'])?.toString() ?? '';
    final rawTimestamp =
        (json['searchedAt'] ?? json['timestamp']) as String? ?? '';
    return SearchHistoryEntry(
      id: rawId,
      name: json['name'] as String? ?? '',
      categoryName: (json['categoryName'] as String?) ?? 'Place',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.tryParse(rawTimestamp) ?? DateTime.now(),
    );
  }
}

class SearchHistoryService {
  static const String _keyPrefix = 'search_history_';
  static const String _guestSuffix = 'guest';
  static const String _tokenKey = 'access_token';
  static const int maxEntries = 30;

  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';

  Future<String?> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<String> _userKey() async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    return '$_keyPrefix${userId ?? _guestSuffix}';
  }

  static String? _extractUserId(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1];
      final pad = payload.length % 4;
      if (pad != 0) payload = payload + '=' * (4 - pad);
      final jsonString = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final raw = data['sub'] ?? data['_id'] ?? data['id'] ?? data['email'];
      return raw?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchHistoryEntry>> load() async {
    final token = await _accessToken();
    if (token != null) {
      final remote = await _remoteLoad(token);
      if (remote != null) return remote;
    }
    return _localLoad();
  }

  Future<List<SearchHistoryEntry>> add(Place place) async {
    final token = await _accessToken();
    if (token != null) {
      final remote = await _remoteAdd(token, place);
      if (remote != null) return remote;
    }
    return _localAdd(place);
  }

  Future<List<SearchHistoryEntry>> remove(String id) async {
    final token = await _accessToken();
    if (token != null) {
      final remote = await _remoteRemove(token, id);
      if (remote != null) return remote;
    }
    return _localRemove(id);
  }

  Future<void> clear() async {
    final token = await _accessToken();
    if (token != null) {
      final ok = await _remoteClear(token);
      if (ok) return;
    }
    await _localClear();
  }

  // ---------- Remote (DB-backed) ----------

  Map<String, String> _authHeaders(String token, {bool json = false}) => {
        'Authorization': 'Bearer $token',
        if (json) 'Content-Type': 'application/json',
      };

  Future<List<SearchHistoryEntry>?> _remoteLoad(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/search-history');
      final res = await http
          .get(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return _parseList(res.body);
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchHistoryEntry>?> _remoteAdd(
    String token,
    Place place,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/search-history');
      final body = jsonEncode({
        'placeId': place.id,
        'name': place.name,
        'categoryName': place.category?.name ?? 'Place',
        'latitude': place.latitude,
        'longitude': place.longitude,
      });
      final res = await http
          .post(uri, headers: _authHeaders(token, json: true), body: body)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      return _parseList(res.body);
    } catch (_) {
      return null;
    }
  }

  Future<List<SearchHistoryEntry>?> _remoteRemove(
    String token,
    String placeId,
  ) async {
    try {
      final uri = Uri.parse('$_baseUrl/search-history/$placeId');
      final res = await http
          .delete(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      return _parseList(res.body);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _remoteClear(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/search-history');
      final res = await http
          .delete(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  List<SearchHistoryEntry> _parseList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return <SearchHistoryEntry>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SearchHistoryEntry.fromJson)
        .toList();
  }

  // ---------- Local (SharedPreferences guest fallback) ----------

  Future<List<SearchHistoryEntry>> _localLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <SearchHistoryEntry>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SearchHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <SearchHistoryEntry>[];
    }
  }

  Future<List<SearchHistoryEntry>> _localAdd(Place place) async {
    final entries = await _localLoad();
    entries.removeWhere((e) => e.id == place.id);
    entries.insert(0, SearchHistoryEntry.fromPlace(place));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    await _localPersist(entries);
    return entries;
  }

  Future<List<SearchHistoryEntry>> _localRemove(String id) async {
    final entries = await _localLoad();
    entries.removeWhere((e) => e.id == id);
    await _localPersist(entries);
    return entries;
  }

  Future<void> _localClear() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.remove(key);
  }

  Future<void> _localPersist(List<SearchHistoryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

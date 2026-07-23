import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';

class FavoritePlace {
  final String placeId;

  /// Khmer place name (place `nameInKhmer`).
  final String name;

  /// Latin place name (place `nameInLatin`); null on entries saved before the
  /// field existed.
  final String? nameLatin;

  final String categoryName;
  final double latitude;
  final double longitude;
  final String? photo;
  final double? averageRating;
  final int? ratingCount;
  final DateTime favoritedAt;

  const FavoritePlace({
    required this.placeId,
    required this.name,
    this.nameLatin,
    required this.categoryName,
    required this.latitude,
    required this.longitude,
    required this.favoritedAt,
    this.photo,
    this.averageRating,
    this.ratingCount,
  });

  /// Place name for the active language ('en' → Latin, else Khmer).
  String localizedName(String languageCode) =>
      localizedPlaceName(name, nameLatin, languageCode);

  factory FavoritePlace.fromPlace(Place p) => FavoritePlace(
    placeId: p.id,
    name: p.nameInKhmer,
    nameLatin: p.nameInLatin,
    categoryName: p.category?.name ?? 'Place',
    latitude: p.latitude,
    longitude: p.longitude,
    photo: p.photos.isNotEmpty ? p.photos.first : null,
    averageRating: p.averageRating,
    ratingCount: p.ratingCount,
    favoritedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'name': name,
    'nameLatin': nameLatin,
    'categoryName': categoryName,
    'latitude': latitude,
    'longitude': longitude,
    'photo': photo,
    'averageRating': averageRating,
    'ratingCount': ratingCount,
    'favoritedAt': favoritedAt.toIso8601String(),
  };

  factory FavoritePlace.fromJson(Map<String, dynamic> json) {
    final rawId = (json['placeId'] ?? json['id'])?.toString() ?? '';
    final rawTimestamp =
        (json['favoritedAt'] ?? json['createdAt']) as String? ?? '';
    return FavoritePlace(
      placeId: rawId,
      name: (json['name'] ?? json['nameInKhmer']) as String? ?? '',
      nameLatin: (json['nameLatin'] ?? json['nameInLatin']) as String?,
      categoryName: (json['categoryName'] as String?) ?? 'Place',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      photo: json['photo'] as String?,
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      ratingCount: (json['ratingCount'] as num?)?.toInt(),
      favoritedAt: DateTime.tryParse(rawTimestamp) ?? DateTime.now(),
    );
  }
}

class FavoritesService {
  static const String _keyPrefix = 'favorites_';
  static const String _guestSuffix = 'guest';
  static const String _tokenKey = 'access_token';

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

  Future<List<FavoritePlace>> load() async {
    final token = await _accessToken();
    if (token != null) {
      final remote = await _remoteLoad(token);
      if (remote != null) return remote;
    }
    return _localLoad();
  }

  Future<List<FavoritePlace>> add(Place place) async {
    final token = await _accessToken();
    if (token == null) {
      return _localAdd(place);
    }
    final remote = await _remoteAdd(token, place);
    if (remote != null) return remote;
    return _localAdd(place);
  }

  Future<List<FavoritePlace>> remove(String placeId) async {
    final token = await _accessToken();
    if (token == null) {
      return _localRemove(placeId);
    }
    final remote = await _remoteRemove(token, placeId);
    if (remote != null) return remote;
    return _localRemove(placeId);
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

  Future<List<FavoritePlace>?> _remoteLoad(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/favorites');
      final res = await http
          .get(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return _parseList(res.body);
    } catch (_) {
      return null;
    }
  }

  Future<List<FavoritePlace>?> _remoteAdd(String token, Place place) async {
    final uri = Uri.parse('$_baseUrl/favorites');
    try {
      final body = jsonEncode({
        'placeId': place.id,
        'name': place.nameInKhmer,
        'nameLatin': place.nameInLatin,
        'categoryName': place.category?.name ?? 'Place',
        'latitude': place.latitude,
        'longitude': place.longitude,
        if (place.photos.isNotEmpty) 'photo': place.photos.first,
        if (place.averageRating != null) 'averageRating': place.averageRating,
        if (place.ratingCount != null) 'ratingCount': place.ratingCount,
      });
      final res = await http
          .post(uri, headers: _authHeaders(token, json: true), body: body)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      return _parseList(res.body);
    } catch (e) {
      return null;
    }
  }

  Future<List<FavoritePlace>?> _remoteRemove(
    String token,
    String placeId,
  ) async {
    final uri = Uri.parse('$_baseUrl/favorites/$placeId');
    try {
      final res = await http
          .delete(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      return _parseList(res.body);
    } catch (e) {
      return null;
    }
  }

  Future<bool> _remoteClear(String token) async {
    try {
      final uri = Uri.parse('$_baseUrl/favorites');
      final res = await http
          .delete(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  List<FavoritePlace> _parseList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return <FavoritePlace>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FavoritePlace.fromJson)
        .toList();
  }

  // ---------- Local (SharedPreferences guest fallback) ----------

  Future<List<FavoritePlace>> _localLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <FavoritePlace>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FavoritePlace.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <FavoritePlace>[];
    }
  }

  Future<List<FavoritePlace>> _localAdd(Place place) async {
    final entries = await _localLoad();
    entries.removeWhere((e) => e.placeId == place.id);
    entries.insert(0, FavoritePlace.fromPlace(place));
    await _localPersist(entries);
    return entries;
  }

  Future<List<FavoritePlace>> _localRemove(String placeId) async {
    final entries = await _localLoad();
    entries.removeWhere((e) => e.placeId == placeId);
    await _localPersist(entries);
    return entries;
  }

  Future<void> _localClear() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.remove(key);
  }

  Future<void> _localPersist(List<FavoritePlace> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

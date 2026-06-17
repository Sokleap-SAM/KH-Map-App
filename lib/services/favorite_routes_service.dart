import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_route.dart';

/// Persists the user's saved transit routes against `/transit/favorites`,
/// mirroring the token-or-local-guest auth logic of [FavoritesService].
///
/// The backend stores only the endpoints (`{ user, label?, origin,
/// destination }`); the journey is re-planned on demand by feeding those
/// endpoints back into the normal transit planner — so no leg/stop data is
/// persisted here.
class FavoriteRoutesService {
  static const String _keyPrefix = 'favorite_routes_';
  static const String _guestSuffix = 'guest';
  static const String _tokenKey = 'access_token';

  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';

  /// Bumped whenever the saved-routes set changes (add / remove), so screens
  /// kept alive in the app's [IndexedStack] (e.g. the bookmark tab) can reload
  /// without waiting for a hot restart or manual pull-to-refresh.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<String?> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<String?> _userId() async => _extractUserId(await _accessToken());

  Future<String> _userKey() async {
    final userId = await _userId();
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

  Map<String, String> _authHeaders(String? token, {bool json = false}) => {
    if (token != null) 'Authorization': 'Bearer $token',
    if (json) 'Content-Type': 'application/json',
  };

  // ---------- Load ----------

  Future<List<FavoriteRoute>> load() async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    if (token != null && userId != null) {
      final remote = await _remoteLoad(token, userId);
      if (remote != null) return remote;
    }
    return _localLoad();
  }

  Future<List<FavoriteRoute>?> _remoteLoad(String token, String userId) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/transit/favorites',
      ).replace(queryParameters: {'user': userId});
      final res = await http
          .get(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return _parseList(res.body);
    } catch (e) {
      debugPrint('[FavRoutes] load failed: $e');
      return null;
    }
  }

  // ---------- Add ----------

  Future<FavoriteRoute> add({
    required FavoriteRouteEndpoint origin,
    required FavoriteRouteEndpoint destination,
    String? label,
  }) async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    FavoriteRoute? saved;
    if (token != null && userId != null) {
      saved = await _remoteAdd(
        token: token,
        userId: userId,
        origin: origin,
        destination: destination,
        label: label,
      );
      if (saved == null) {
        debugPrint('[FavRoutes] add: remote failed — falling back to LOCAL');
      }
    }
    saved ??= await _localAdd(
      origin: origin,
      destination: destination,
      label: label,
    );
    changes.value++;
    return saved;
  }

  Future<FavoriteRoute?> _remoteAdd({
    required String token,
    required String userId,
    required FavoriteRouteEndpoint origin,
    required FavoriteRouteEndpoint destination,
    String? label,
  }) async {
    final uri = Uri.parse('$_baseUrl/transit/favorites');
    try {
      final body = jsonEncode({
        'user': userId,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        'origin': origin.toJson(),
        'destination': destination.toJson(),
      });
      final res = await http
          .post(uri, headers: _authHeaders(token, json: true), body: body)
          .timeout(const Duration(seconds: 10));
      debugPrint('[FavRoutes] POST $uri -> ${res.statusCode}');
      if (res.statusCode != 200 && res.statusCode != 201) return null;
      return FavoriteRoute.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('[FavRoutes] POST threw: $e');
      return null;
    }
  }

  // ---------- Remove ----------

  Future<void> remove(String id) async {
    final token = await _accessToken();
    if (token != null && !_isLocalId(id)) {
      final ok = await _remoteRemove(token, id);
      if (ok) {
        changes.value++;
        return;
      }
    }
    await _localRemove(id);
    changes.value++;
  }

  Future<bool> _remoteRemove(String token, String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/transit/favorites/$id');
      final res = await http
          .delete(uri, headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      debugPrint('[FavRoutes] DELETE $uri -> ${res.statusCode}');
      return res.statusCode == 204 ||
          res.statusCode == 200 ||
          res.statusCode == 404;
    } catch (e) {
      debugPrint('[FavRoutes] DELETE threw: $e');
      return false;
    }
  }

  List<FavoriteRoute> _parseList(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return <FavoriteRoute>[];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FavoriteRoute.fromJson)
        .toList();
  }

  // ---------- Local (SharedPreferences guest fallback) ----------

  static const String _localIdPrefix = 'local_';
  bool _isLocalId(String id) => id.startsWith(_localIdPrefix);

  Future<List<FavoriteRoute>> _localLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <FavoriteRoute>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => FavoriteRoute.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <FavoriteRoute>[];
    }
  }

  Future<FavoriteRoute> _localAdd({
    required FavoriteRouteEndpoint origin,
    required FavoriteRouteEndpoint destination,
    String? label,
  }) async {
    final entries = await _localLoad();
    final fav = FavoriteRoute(
      id: '$_localIdPrefix${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      origin: origin,
      destination: destination,
      savedAt: DateTime.now(),
    );
    entries.insert(0, fav);
    await _localPersist(entries);
    return fav;
  }

  Future<void> _localRemove(String id) async {
    final entries = await _localLoad();
    entries.removeWhere((e) => e.id == id);
    await _localPersist(entries);
  }

  Future<void> _localPersist(List<FavoriteRoute> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

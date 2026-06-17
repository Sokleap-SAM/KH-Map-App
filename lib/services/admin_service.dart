import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_route.dart';
import '../models/place.dart';

/// Typed exception carrying the backend's machine-readable message so the UI
/// can surface it. Mirrors DriverApiException.
class AdminApiException implements Exception {
  final int statusCode;
  final String message;
  AdminApiException(this.statusCode, this.message);
  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

/// One item in the bulk route-stops body. A stop is a reference to an existing
/// Place (`placeId`) plus the manually-drawn polyline connecting the PREVIOUS
/// stop to this one.
///
/// Per BulkRouteStopItemDto: [segmentFromPrevious] is a list of `[lng, lat]`
/// pairs whose first vertex matches the previous stop's coords and last vertex
/// matches this stop's coords. The backend requires it for every stop at
/// stopOrder >= 2 and rejects it on stopOrder == 1, so the caller sets it on
/// all stops except the first stop of a brand-new route.
class BulkStopRef {
  final String placeId;
  final List<List<double>>? segmentFromPrevious;

  const BulkStopRef({required this.placeId, this.segmentFromPrevious});

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'segmentFromPrevious': ?segmentFromPrevious,
  };
}

/// How many / which routes reference a given Place
/// (GET /transit/stops/:stopId/routes).
class StopUsage {
  final int count;
  final List<AdminRoute> routes;
  const StopUsage({required this.count, required this.routes});
}

/// HTTP client for the admin route-management endpoints described in the
/// admin frontend brief. Token + base-url handling mirror DriverService.
class AdminService {
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
    throw AdminApiException(r.statusCode, '${_extractMessage(r)} ($path)');
  }

  bool _ok(int code) => code == 200 || code == 201;

  /// GET /transit/routes — every route (lines + circular), for the list.
  Future<List<AdminRoute>> fetchAllRoutes() async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/transit/routes'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final data = jsonDecode(r.body) as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map(AdminRoute.fromJson)
        .toList();
  }

  // ───────────────────────────── Places (stops) ─────────────────────────────

  /// GET /places — all places (the "stops" managed in the Stops tab).
  Future<List<Place>> fetchPlaces() async {
    final r = await http
        .get(Uri.parse('$_baseUrl/places'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final data = jsonDecode(r.body) as List;
    return data.whereType<Map<String, dynamic>>().map(Place.fromJson).toList();
  }

  /// Category id for the `bus_stop` Place category — admin-created stops are
  /// bus stops, so we tag them on create.
  static const String busStopCategoryId = '69e5ea7cfcfc727fba260bcd';

  /// POST /places — create a stop. Body per CreatePlaceDto:
  /// `{ name, category, location: [lng, lat] }`.
  Future<Place> createPlace({
    required String name,
    required double longitude,
    required double latitude,
  }) async {
    final r = await http
        .post(
          Uri.parse('$_baseUrl/places'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(_placeBody(name, longitude, latitude)),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
    return Place.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// PATCH /places/:id — edit a stop. Same body-shape caveat as createPlace.
  Future<Place> updatePlace(
    String placeId, {
    String? name,
    double? longitude,
    double? latitude,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      if (longitude != null && latitude != null)
        'location': [longitude, latitude],
    };
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/places/$placeId'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
    return Place.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// DELETE /places/:id. Throws AdminApiException(409|400) when the stop is
  /// still referenced by a route — the caller can then call [fetchStopRoutes].
  Future<void> deletePlace(String placeId) async {
    final r = await http
        .delete(
          Uri.parse('$_baseUrl/places/$placeId'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  // Backend CreatePlaceDto expects GeoJSON-style `location: [lng, lat]`.
  Map<String, dynamic> _placeBody(String name, double lng, double lat) => {
    'name': name,
    'category': busStopCategoryId,
    'location': [lng, lat],
  };

  /// GET /transit/stops/:stopId/routes — routes that reference a place.
  /// NOTE: response shape parsed tolerantly (list of route docs, or
  /// `{ count, routes }`); confirm against the controller.
  Future<StopUsage> fetchStopRoutes(String placeId) async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/transit/stops/$placeId/routes'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final decoded = jsonDecode(r.body);
    List rawRoutes = const [];
    int? count;
    if (decoded is List) {
      rawRoutes = decoded;
    } else if (decoded is Map) {
      if (decoded['routes'] is List) rawRoutes = decoded['routes'] as List;
      if (decoded['count'] is num) count = (decoded['count'] as num).toInt();
    }
    final routes = rawRoutes
        .whereType<Map<String, dynamic>>()
        .map(AdminRoute.fromJson)
        .toList();
    return StopUsage(count: count ?? routes.length, routes: routes);
  }

  /// GET /transit/admin/suggest-path — road-snapped polyline between two
  /// points (Valhalla, can take a few seconds). Query params per SuggestPathDto:
  /// fromLng, fromLat, toLng, toLat.
  ///
  /// Returns the path as ordered LatLng vertices including both endpoints.
  /// NOTE: response shape is parsed tolerantly (coordinates / path.coordinates
  /// / raw list of [lng,lat]); confirm against the controller if it differs.
  Future<List<LatLng>> suggestPath({
    required LatLng from,
    required LatLng to,
  }) async {
    final uri = Uri.parse('$_baseUrl/transit/admin/suggest-path').replace(
      queryParameters: {
        'fromLng': from.longitude.toString(),
        'fromLat': from.latitude.toString(),
        'toLng': to.longitude.toString(),
        'toLat': to.latitude.toString(),
      },
    );
    final r = await http
        .get(uri, headers: await _authHeaders())
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) _throwFor(r);
    return _parsePathCoordinates(jsonDecode(r.body));
  }

  /// Extracts an ordered `[lng, lat]` list from common response shapes and
  /// converts to LatLng (latlong2 is lat,lng).
  List<LatLng> _parsePathCoordinates(dynamic decoded) {
    List? coords;
    if (decoded is List) {
      coords = decoded;
    } else if (decoded is Map) {
      final c =
          decoded['coordinates'] ?? decoded['path'] ?? decoded['polyline'];
      if (c is List) {
        coords = c;
      } else if (c is Map && c['coordinates'] is List) {
        coords = c['coordinates'] as List; // GeoJSON LineString
      }
    }
    if (coords == null) {
      throw AdminApiException(200, 'suggest-path response had no coordinates');
    }
    return coords.whereType<List>().map((pt) {
      return LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
    }).toList();
  }

  /// POST /transit/admin/route-stops/bulk
  ///
  /// Create mode: pass [name]/[code]/[isLine] + [stops] (existing place refs);
  /// the backend creates the route + BusRouteStops in one call.
  /// Append mode: pass [routeId]; the [stops] are added to the route's tail.
  /// Returns the affected route id.
  Future<String> bulkCreateRouteStops({
    required List<BulkStopRef> stops,
    String? routeId,
    String? name,
    String? code,
    bool? isLine,
  }) async {
    final body = <String, dynamic>{
      'stops': stops.map((s) => s.toJson()).toList(),
      'routeId': ?routeId,
      'name': ?name,
      'code': ?code,
      'isLine': ?isLine,
    };
    final r = await http
        .post(
          Uri.parse('$_baseUrl/transit/admin/route-stops/bulk'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (!_ok(r.statusCode)) _throwFor(r);
    // Append mode already knows the id; otherwise dig it out of the response.
    if (routeId != null) return routeId;
    final decoded = jsonDecode(r.body);
    final id = _routeIdFrom(decoded);
    if (id == null) {
      throw AdminApiException(
        r.statusCode,
        'Route created but response had no route id',
      );
    }
    return id;
  }

  String? _routeIdFrom(dynamic decoded) {
    if (decoded is Map) {
      // { _id } | { route: { _id } } | { routeId }
      if (decoded['_id'] is String) return decoded['_id'] as String;
      if (decoded['routeId'] is String) return decoded['routeId'] as String;
      final route = decoded['route'];
      if (route is Map && route['_id'] is String) return route['_id'] as String;
      // { stops: [{ route: "<id>" | { _id } }] }
      final stops = decoded['stops'];
      if (stops is List && stops.isNotEmpty) return _routeIdFrom(stops.first);
    }
    return null;
  }

  /// PATCH /transit/route-stops/:id — edit a single stop's name/coordinates.
  /// NOTE: this does NOT re-snap the polyline; the caller must warn the admin
  /// when coordinates change.
  Future<void> updateRouteStop(
    String stopId, {
    String? name,
    double? longitude,
    double? latitude,
  }) async {
    final body = <String, dynamic>{
      'name': ?name,
      'longitude': ?longitude,
      'latitude': ?latitude,
    };
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/transit/route-stops/$stopId'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  /// DELETE /transit/route-stops/:id
  Future<void> deleteRouteStop(String stopId) async {
    final r = await http
        .delete(
          Uri.parse('$_baseUrl/transit/route-stops/$stopId'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  /// DELETE /transit/routes/:id
  Future<void> deleteRoute(String routeId) async {
    final r = await http
        .delete(
          Uri.parse('$_baseUrl/transit/routes/$routeId'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
  }
}

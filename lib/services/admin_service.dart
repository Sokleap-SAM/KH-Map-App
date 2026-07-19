import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_dashboard.dart';
import '../models/admin_route.dart';
import '../models/place.dart';
import '../models/place_category.dart';

/// Typed exception carrying the backend's machine-readable message so the UI
/// can surface it. Mirrors DriverApiException.
class AdminApiException implements Exception {
  final int statusCode;
  final String message;
  AdminApiException(this.statusCode, this.message);
  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

/// One item in the bulk route-stops body: a reference to an existing Place
/// (`placeId`) plus, optionally, how to build the segment from the PREVIOUS
/// stop to this one. All geometry is road-snapped server-side (Valhalla):
///
/// - neither field set → the backend computes the road path (default),
/// - [vias] (`[lng, lat]` each, max 10) → computed, forced through the vias,
/// - [segmentFromPrevious] → stored verbatim (send suggest-path output the
///   admin approved).
///
/// The first stop of a brand-new route must send neither.
class BulkStopRef {
  final String placeId;
  final List<List<double>>? vias;
  final List<List<double>>? segmentFromPrevious;

  const BulkStopRef({
    required this.placeId,
    this.vias,
    this.segmentFromPrevious,
  });

  Map<String, dynamic> toJson() => {
    'placeId': placeId,
    'vias': ?vias,
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

  /// GET /transit/admin/dashboard — live/simulation mode + split
  /// current/in-period counts for the given [period] (admin only).
  Future<AdminDashboard> fetchDashboard([
    DashboardPeriod period = DashboardPeriod.day,
  ]) async {
    final r = await http
        .get(
          Uri.parse(
            '$_baseUrl/transit/admin/dashboard',
          ).replace(queryParameters: {'period': period.value}),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    return AdminDashboard.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

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

  /// GET /places/stops — every Bus Stop place (category populated), the set
  /// managed in the Stops tab.
  Future<List<Place>> fetchPlaces() async {
    final r = await http
        .get(Uri.parse('$_baseUrl/places/stops'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final data = jsonDecode(r.body) as List;
    return data.whereType<Map<String, dynamic>>().map(Place.fromJson).toList();
  }

  /// GET /places/:id — one place with full data (photos, category).
  Future<Place> fetchPlace(String placeId) async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/places/$placeId'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    return Place.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// GET /places — every place (all categories), for the Places screen.
  Future<List<Place>> fetchAllPlaces() async {
    final r = await http
        .get(Uri.parse('$_baseUrl/places'), headers: await _authHeaders())
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final data = jsonDecode(r.body) as List;
    return data.whereType<Map<String, dynamic>>().map(Place.fromJson).toList();
  }

  /// GET /places/categories — place categories for the filter / picker.
  Future<List<PlaceCategory>> fetchCategories() async {
    final r = await http
        .get(
          Uri.parse('$_baseUrl/places/categories'),
          headers: await _authHeaders(),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) _throwFor(r);
    final data = jsonDecode(r.body) as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map(PlaceCategory.fromJson)
        .toList();
  }

  /// POST /places — create a place in a chosen category. multipart/form-data:
  /// `nameInKhmer`, optional `nameInLatin`, `category`, `location` (JSON string
  /// `[lng, lat]`), plus optional `photos` files (uploaded to Cloudinary by the
  /// backend).
  Future<Place> createPlaceInCategory({
    required String nameInKhmer,
    required String nameInLatin,
    required double longitude,
    required double latitude,
    required String categoryId,
    List<String> photoPaths = const [],
  }) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/places'));
    final token = await _token();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['nameInKhmer'] = nameInKhmer;
    req.fields['nameInLatin'] = nameInLatin;
    req.fields['category'] = categoryId;
    req.fields['location'] = jsonEncode([longitude, latitude]);
    for (final path in photoPaths) {
      req.files.add(await http.MultipartFile.fromPath('photos', path));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final r = await http.Response.fromStream(streamed);
    if (!_ok(r.statusCode)) _throwFor(r);
    return Place.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// POST /places/stops — create a bus stop. multipart/form-data body:
  /// `nameInKhmer`, optional `nameInLatin`, `location` (JSON string
  /// `[lng, lat]`), optional `photos` files. The backend auto-assigns the
  /// "Bus Stop" category.
  Future<Place> createPlace({
    required String nameInKhmer,
    required String nameInLatin,
    required double longitude,
    required double latitude,
    List<http.MultipartFile>? photos,
  }) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/places/stops'),
    );
    final token = await _token();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['nameInKhmer'] = nameInKhmer;
    req.fields['nameInLatin'] = nameInLatin;
    req.fields['location'] = jsonEncode([longitude, latitude]);
    if (photos != null) req.files.addAll(photos);

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final r = await http.Response.fromStream(streamed);
    if (!_ok(r.statusCode)) _throwFor(r);
    return Place.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  /// PATCH /places/:id — edit a place. multipart/form-data so new `photos`
  /// files can be appended (the controller wraps this route in a photos
  /// FilesInterceptor). Only the provided fields are sent.
  ///
  /// [keepPhotoUrls], when non-null, is the list of EXISTING photo URLs to
  /// keep — sent as the `photos` field so the backend can drop the removed
  /// ones. New uploads in [photoPaths] are appended. (Requires UpdatePlaceDto
  /// to accept a `photos: string[]` of URLs to keep.)
  Future<Place> updatePlace(
    String placeId, {
    String? nameInKhmer,
    String? nameInLatin,
    double? longitude,
    double? latitude,
    String? categoryId,
    List<String> photoPaths = const [],
    List<String>? keepPhotoUrls,
  }) async {
    final req = http.MultipartRequest(
      'PATCH',
      Uri.parse('$_baseUrl/places/$placeId'),
    );
    final token = await _token();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (nameInKhmer != null) req.fields['nameInKhmer'] = nameInKhmer;
    if (nameInLatin != null) req.fields['nameInLatin'] = nameInLatin;
    if (categoryId != null) req.fields['category'] = categoryId;
    if (longitude != null && latitude != null) {
      req.fields['location'] = jsonEncode([longitude, latitude]);
    }
    if (keepPhotoUrls != null) {
      req.fields['photos'] = jsonEncode(keepPhotoUrls);
    }
    for (final path in photoPaths) {
      req.files.add(await http.MultipartFile.fromPath('photos', path));
    }
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final r = await http.Response.fromStream(streamed);
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

  /// POST /transit/admin/suggest-path — road-snapped polyline between two
  /// points (Valhalla, can take a few seconds). Body: `from`/`to` as
  /// `[lng, lat]`, plus optional [vias] (`[lng, lat]` each, max 10) the path
  /// is forced through when the default road is not the real bus corridor.
  ///
  /// The returned polyline starts/ends at the ROAD nearest each stop, not at
  /// the stop coordinates — render it as-is, never prepend/append the stops.
  /// Throws 503 when Valhalla is down or no drivable road connects the points.
  Future<List<LatLng>> suggestPath({
    required LatLng from,
    required LatLng to,
    List<LatLng> vias = const [],
  }) async {
    final body = <String, dynamic>{
      'from': [from.longitude, from.latitude],
      'to': [to.longitude, to.latitude],
      if (vias.isNotEmpty)
        'vias': [
          for (final v in vias) [v.longitude, v.latitude],
        ],
    };
    final r = await http
        .post(
          Uri.parse('$_baseUrl/transit/admin/suggest-path'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200 && r.statusCode != 201) _throwFor(r);
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
    String? color,
    String? direction,
  }) async {
    final body = <String, dynamic>{
      'stops': stops.map((s) => s.toJson()).toList(),
      'routeId': ?routeId,
      'name': ?name,
      'code': ?code,
      'isLine': ?isLine,
      'color': ?color,
      'direction': ?direction,
    };
    final r = await http
        .post(
          Uri.parse('$_baseUrl/transit/admin/route-stops/bulk'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 200));
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

  /// PATCH /transit/routes/:id — flip just the route's status
  /// ('active' | 'inactive'). Lightweight partial update for the list toggle.
  Future<void> setRouteStatus(String routeId, String status) async {
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/transit/routes/$routeId'),
          headers: await _authHeaders(json: true),
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 10));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  /// PATCH /transit/routes/:id — edit a route's metadata (no stops/segments).
  /// Sends the full editable field set; `code`/`direction` may be null (a loop
  /// has no direction). NOTE: endpoint path + UpdateRouteDto field names are
  /// assumed from the BusRoute schema — confirm if the backend differs.
  Future<void> updateRoute(
    String routeId, {
    required String name,
    String? code,
    required String color,
    required bool isLine,
    String? direction,
    required String status,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'code': code,
      'color': color,
      'isLine': isLine,
      'direction': direction,
      'status': status,
    };
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/transit/routes/$routeId'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  /// PATCH /transit/route-stops/:id — fix ONE stop. Exactly one of:
  ///
  /// - [vias] (`[lng, lat]` each) — wrong road: the incoming segment is
  ///   recomputed through the vias,
  /// - [waypoints] — full replacement polyline (approved suggest-path output),
  /// - [placeId] — wrong place: sent as `stop`; BOTH adjacent segments are
  ///   recomputed.
  ///
  /// Editing the incoming segment re-stitches the NEXT stop's segment
  /// server-side, so after a successful PATCH the caller must re-fetch the
  /// route's stop list — up to TWO stops' segments may have changed.
  Future<void> updateRouteStop(
    String stopId, {
    List<List<double>>? vias,
    List<List<double>>? waypoints,
    String? placeId,
  }) async {
    final body = <String, dynamic>{
      'vias': ?vias,
      'waypoints': ?waypoints,
      'stop': ?placeId,
    };
    final r = await http
        .patch(
          Uri.parse('$_baseUrl/transit/route-stops/$stopId'),
          headers: await _authHeaders(json: true),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (!_ok(r.statusCode)) _throwFor(r);
  }

  /// DELETE /transit/route-stops/:id — the backend heals the chain (next
  /// segment recomputed, stopOrders re-packed), so re-fetch the stop list
  /// after. Throws 503 when Valhalla is down (the delete is aborted).
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

// transit-service

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/route_plan.dart';
import '../models/route_stop.dart';
import '../models/transit_route.dart';
import '../models/trip.dart';
import '../models/trip_eta.dart';

class TransitService {
  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';

  Future<List<TransitRoute>> fetchLineRoutes() async {
    final uri = Uri.parse('$_baseUrl/transit/routes/lines');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load line routes');
    }
    final List data = jsonDecode(response.body) as List;
    return data
        .map((e) => TransitRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TransitRoute>> fetchActiveRoutes() async {
    final uri = Uri.parse('$_baseUrl/transit/routes/active');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load transit routes');
    }
    final List data = jsonDecode(response.body) as List;
    return data
        .map((e) => TransitRoute.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<RouteStop>> fetchRouteStops(String routeId) async {
    final uri = Uri.parse('$_baseUrl/transit/routes/$routeId/stops');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load stops for route $routeId');
    }
    final List data = jsonDecode(response.body) as List;
    final stops = <RouteStop>[];
    for (final e in data) {
      if (e is! Map<String, dynamic>) continue;
      try {
        stops.add(RouteStop.fromJson(e));
      } catch (err) {
        // Corrupt entry — e.g. an orphaned stop whose place was deleted
        // (`stop: null`). Skip it; one bad stop must not blank the route.
        debugPrint('Skipping corrupt stop on route $routeId: $err');
      }
    }
    return stops;
  }

  Future<List<Trip>> fetchActiveTrips() async {
    final uri = Uri.parse('$_baseUrl/transit/trips/active');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load active trips');
    }
    final List data = jsonDecode(response.body) as List;
    return data.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// One-shot ETA snapshot. Returns `null` when the trip has no live
  /// position yet — callers should fall back to MQTT-derived ETA.
  Future<TripEtaSnapshot?> fetchTripEta(String tripId) async {
    final uri = Uri.parse('$_baseUrl/transit/trips/$tripId/eta');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch trip ETA (${response.statusCode})');
    }
    if (response.body.isEmpty || response.body.trim() == 'null') return null;
    final decoded = jsonDecode(response.body);
    if (decoded == null) return null;
    return TripEtaSnapshot.fromJson(decoded as Map<String, dynamic>);
  }

  Future<Trip> startTrip(String id) async {
    final uri = Uri.parse('$_baseUrl/transit/trips/$id/start');
    final response = await http.post(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to start trip');
    }
    return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Trip> advanceTrip(String id) async {
    final uri = Uri.parse('$_baseUrl/transit/trips/$id/advance');
    final response = await http.post(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to advance trip');
    }
    return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RoutePlanResult> fetchRoutePlan({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String type = 'transit',
    // Transit planning (walk + bus legs + transfers) is much heavier than a
    // single walk query, so callers give the first fetch a longer budget.
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = Uri.parse('$_baseUrl/transit/plan').replace(
      queryParameters: {
        'originLng': originLng.toString(),
        'originLat': originLat.toString(),
        'destLng': destLng.toString(),
        'destLat': destLat.toString(),
        'type': type,
      },
    );
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch route plan (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return RoutePlanResult.fromJson(body);
  }
}

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
    final trips = <Trip>[];
    for (final e in data) {
      if (e is! Map<String, dynamic>) continue;
      try {
        trips.add(Trip.fromJson(e));
      } catch (err) {
        // Same rule as route stops: one unparseable trip must not empty the
        // whole map. `_trips` gates MQTT rendering, so throwing here used to
        // mean every live bus was silently dropped.
        debugPrint('Skipping corrupt trip ${e['_id']}: $err');
      }
    }
    return trips;
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

  /// One-shot fetch of a single trip by id. Fallback for the bus-detail view
  /// when the trip isn't in the active-trips list (e.g. it's broadcasting over
  /// MQTT but `/transit/trips/active` doesn't currently return it). Returns null
  /// on 404 / empty body so the caller can fall back gracefully.
  Future<Trip?> fetchTripById(String id) async {
    final uri = Uri.parse('$_baseUrl/transit/trips/$id');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch trip (${response.statusCode})');
    }
    if (response.body.isEmpty || response.body.trim() == 'null') return null;
    return Trip.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
    // Route ids the user is currently committed to. On a triggered (off-route)
    // re-plan, nudges the ranking toward the committed journey so it isn't
    // silently swapped for a different "fastest". Omit for normal planning.
    List<String> preferRouteIds = const [],
  }) async {
    final uri = Uri.parse('$_baseUrl/transit/plan').replace(
      queryParameters: {
        'originLng': originLng.toString(),
        'originLat': originLat.toString(),
        'destLng': destLng.toString(),
        'destLat': destLat.toString(),
        'type': type,
        if (preferRouteIds.isNotEmpty) 'preferRouteIds': preferRouteIds.join(','),
      },
    );
    final response = await http.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch route plan (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    return RoutePlanResult.fromJson(body);
  }

  /// ETA to a specific [stopId] on the live trip [tripId], from
  /// `GET /transit/eta`. Cheap enough to poll per active trip. Returns `null`
  /// when the trip has no live position yet (404) so callers can fall back to
  /// a locally-derived estimate.
  Future<StopEta?> fetchStopEta({
    required String tripId,
    required String stopId,
  }) async {
    final uri = Uri.parse('$_baseUrl/transit/eta').replace(
      queryParameters: {'tripId': tripId, 'stopId': stopId},
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch stop ETA (${response.statusCode})');
    }
    if (response.body.isEmpty || response.body.trim() == 'null') return null;
    return StopEta.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}

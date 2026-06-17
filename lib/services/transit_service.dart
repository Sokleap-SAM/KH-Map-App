// transit-service

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/route_plan.dart';
import '../models/route_stop.dart';
import '../models/transit_route.dart';
import '../models/trip.dart';

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
    return data
        .map((e) => RouteStop.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch route plan (${response.statusCode})');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    // FIX #5: Removed the large debug debugPrint block — not suitable for
    // production builds. Re-add behind a kDebugMode guard if needed:
    //
    //   if (kDebugMode) {
    //     debugPrint('[TransitService] found=${body['found']}');
    //   }

    return RoutePlanResult.fromJson(body);
  }
}

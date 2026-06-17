import 'dart:async';

import 'package:flutter/material.dart';

import '../models/route_stop.dart';
import '../models/transit_route.dart';
import '../models/trip.dart';
import '../services/transit_service.dart';

class TransitProvider extends ChangeNotifier {
  final TransitService _service = TransitService();

  // ── Live trips ────────────────────────────────────────────────────────────
  List<Trip> _trips = [];
  bool _loading = false;
  String? _error;
  Timer? _pollTimer;

  List<Trip> get trips => _trips;
  bool get loading => _loading;
  String? get error => _error;

  // Poll every 3 s while any trip is in-progress, 10 s otherwise.
  static const Duration _fastPoll = Duration(seconds: 3);
  static const Duration _slowPoll = Duration(seconds: 10);
  Duration _currentInterval = _slowPoll;

  // ── Line routes / stops / colors ──────────────────────────────────────────
  static const List<Color> _palette = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.amber,
  ];

  List<TransitRoute> _lineRoutes = [];
  Map<String, List<RouteStop>> _routeStops = {};
  Map<String, Color> _routeColors = {};
  bool _routesLoading = false;
  String? _routesError;

  List<TransitRoute> get lineRoutes => _lineRoutes;
  Map<String, List<RouteStop>> get routeStops => _routeStops;
  Map<String, Color> get routeColors => _routeColors;
  bool get routesLoading => _routesLoading;
  String? get routesError => _routesError;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Fetches active trips and line routes, then starts an adaptive poll cycle.
  Future<void> init() async {
    await Future.microtask(() async {
      await loadRoutes();
      await refresh();
    });
    _schedulePoll();
  }

  Future<void> loadRoutes() async {
    _routesLoading = true;
    _routesError = null;
    notifyListeners();
    try {
      final routes = await _service.fetchLineRoutes();
      final stopsMap = <String, List<RouteStop>>{};
      final colors = <String, Color>{};
      for (var i = 0; i < routes.length; i++) {
        stopsMap[routes[i].id] = await _service.fetchRouteStops(routes[i].id);
        colors[routes[i].id] = _palette[i % _palette.length];
      }
      _lineRoutes = routes;
      _routeStops = stopsMap;
      _routeColors = colors;
    } catch (e) {
      _routesError = e.toString();
      debugPrint('TransitProvider: failed to load routes: $e');
    } finally {
      _routesLoading = false;
      notifyListeners();
    }
  }

  // ── Trip polling ──────────────────────────────────────────────────────────

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(_currentInterval, () async {
      await refresh();
      _schedulePoll();
    });
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _trips = await _service.fetchActiveTrips();
      final hasInProgress = _trips.any((t) => t.isInProgress);
      final desired = hasInProgress ? _fastPoll : _slowPoll;
      if (desired != _currentInterval) _currentInterval = desired;
    } catch (e) {
      _error = e.toString();
      debugPrint('TransitProvider: failed to refresh trips: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> startTrip(String id) async {
    try {
      await _service.startTrip(id);
      await refresh();
    } catch (e) {
      debugPrint('TransitProvider: failed to start trip $id: $e');
      rethrow;
    }
  }

  Future<void> advanceTrip(String id) async {
    try {
      await _service.advanceTrip(id);
      await refresh();
    } catch (e) {
      debugPrint('TransitProvider: failed to advance trip $id: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

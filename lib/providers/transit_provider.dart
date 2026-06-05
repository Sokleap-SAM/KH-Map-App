import 'dart:async';

import 'package:flutter/material.dart';

import '../models/route_stop.dart';
import '../models/transit_route.dart';
import '../models/trip.dart';
import '../services/mqtt_service.dart';
import '../services/transit_service.dart';

/// Owns transit data for the map.
///
/// **Live positions** come from MQTT — see [setSubscribedRoutes]. Each
/// position message arrives at roughly the simulator's tick rate (~1 s) and
/// patches the matching trip in [_trips] via [Trip.copyWith].
///
/// **Trip metadata** (names, stops, bus image, status) comes from a slow
/// HTTP poll of `GET /transit/trips/active` every [_metadataInterval]. The
/// poll only refreshes metadata — position fields from MQTT are preserved
/// when newer than the HTTP snapshot.
class TransitProvider extends ChangeNotifier {
  final TransitService _service = TransitService();
  final MqttService _mqtt = MqttService.instance;

  // ── Trips ────────────────────────────────────────────────────────────────
  List<Trip> _trips = [];
  bool _loading = false;
  String? _error;
  Timer? _metadataTimer;
  Timer? _staleCheckTimer;
  Timer? _refreshDebounce;

  /// Active MQTT subscriptions: routeId → unsubscribe callback (still being
  /// resolved while the future hasn't completed).
  final Map<String, Future<VoidCallback>> _routeSubs = {};

  /// Last MQTT update time per tripId. Drives stale-removal so dead trips
  /// fall off the map without waiting for the next metadata refresh.
  final Map<String, DateTime> _lastSeen = {};

  List<Trip> get trips => _trips;
  bool get loading => _loading;
  String? get error => _error;

  static const Duration _metadataInterval = Duration(seconds: 60);
  static const Duration _staleCheckInterval = Duration(seconds: 2);
  static const Duration _staleAfter = Duration(seconds: 10);

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

  Future<void> init() async {
    await Future.microtask(() async {
      await loadRoutes();
      await refresh();
    });
    _scheduleMetadataPoll();
    _scheduleStaleCheck();
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

  // ── Metadata refresh (slow HTTP poll) ─────────────────────────────────────

  void _scheduleMetadataPoll() {
    _metadataTimer?.cancel();
    _metadataTimer = Timer(_metadataInterval, () async {
      await refresh();
      _scheduleMetadataPoll();
    });
  }

  /// Pulls trip metadata from HTTP. Preserves any MQTT-driven position
  /// fields that are newer than what the snapshot reports.
  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final fresh = await _service.fetchActiveTrips();
      final merged = <Trip>[];
      for (final t in fresh) {
        final existingIdx = _trips.indexWhere((e) => e.id == t.id);
        if (existingIdx == -1) {
          merged.add(t);
        } else {
          final existing = _trips[existingIdx];
          // If we have an MQTT-supplied position, keep it — it's almost
          // certainly fresher than the HTTP snapshot.
          if (existing.recordedAt != null) {
            merged.add(
              t.copyWith(
                currentLocation: existing.currentLocation,
                currentStopIndex: existing.currentStopIndex,
                heading: existing.heading,
                speed: existing.speed,
                recordedAt: existing.recordedAt,
              ),
            );
          } else {
            merged.add(t);
          }
        }
      }
      _trips = merged;
    } catch (e) {
      _error = e.toString();
      debugPrint('TransitProvider: failed to refresh trips: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── MQTT subscriptions ────────────────────────────────────────────────────

  /// Idempotent: subscribe to position topics for [routeIds], unsubscribe
  /// from any routes no longer in the set. Call this whenever the route
  /// filter / active plan changes.
  Future<void> setSubscribedRoutes(Set<String> routeIds) async {
    final current = _routeSubs.keys.toSet();
    final toAdd = routeIds.difference(current);
    final toRemove = current.difference(routeIds);

    for (final id in toRemove) {
      final pending = _routeSubs.remove(id);
      if (pending != null) {
        try {
          (await pending)();
        } catch (e) {
          debugPrint('TransitProvider: unsubscribe failed for $id: $e');
        }
      }
      // Per spec: when unsubscribing, immediately drop any markers whose
      // trip belonged to that route — don't wait for the stale timer.
      final droppedIds = _trips
          .where((t) => t.routeId == id)
          .map((t) => t.id)
          .toSet();
      if (droppedIds.isNotEmpty) {
        _trips = _trips.where((t) => !droppedIds.contains(t.id)).toList();
        droppedIds.forEach(_lastSeen.remove);
      }
    }

    for (final id in toAdd) {
      _routeSubs[id] = _mqtt.subscribeToRoute(id, _handlePosition);
    }

    if (toAdd.isNotEmpty || toRemove.isNotEmpty) notifyListeners();
  }

  void _handlePosition(BusPosition pos) {
    final idx = _trips.indexWhere((t) => t.id == pos.tripId);
    if (idx == -1) {
      // First time we've heard about this trip — debounce a metadata
      // fetch so we can render its name/stops on next paint.
      _maybeRequestMetadataRefresh();
      return;
    }
    _trips[idx] = _trips[idx].copyWith(
      currentLocation: pos.location,
      currentStopIndex: pos.currentStopIndex,
      heading: pos.heading,
      speed: pos.speed,
      recordedAt: pos.recordedAt,
      notDepartingUntilMs: pos.notDepartingUntilMs,
    );
    _lastSeen[pos.tripId] = DateTime.now();
    notifyListeners();
  }

  void _maybeRequestMetadataRefresh() {
    if (_refreshDebounce?.isActive ?? false) return;
    _refreshDebounce = Timer(const Duration(seconds: 3), refresh);
  }

  // ── Stale-marker removal ──────────────────────────────────────────────────

  void _scheduleStaleCheck() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(_staleCheckInterval, (_) {
      if (_lastSeen.isEmpty) return;
      final cutoff = DateTime.now().subtract(_staleAfter);
      final stale = <String>{};
      _lastSeen.forEach((tripId, ts) {
        if (ts.isBefore(cutoff)) stale.add(tripId);
      });
      if (stale.isEmpty) return;
      _trips = _trips.where((t) => !stale.contains(t.id)).toList();
      stale.forEach(_lastSeen.remove);
      notifyListeners();
    });
  }

  // ── Trip lifecycle helpers (unchanged HTTP commands) ──────────────────────

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
    _metadataTimer?.cancel();
    _staleCheckTimer?.cancel();
    _refreshDebounce?.cancel();
    // Fire-and-forget all unsubs — we're tearing down anyway.
    for (final pending in _routeSubs.values) {
      pending.then((unsub) => unsub()).catchError((_) {});
    }
    _routeSubs.clear();
    super.dispose();
  }
}

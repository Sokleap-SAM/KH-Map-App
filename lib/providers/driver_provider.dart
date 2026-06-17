import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/driver_mqtt_credentials.dart';
import '../models/driver_profile.dart';
import '../models/route_stop.dart' show RouteStop;
import '../models/transit_route.dart';
import '../models/trip.dart';
import '../services/driver_location_publisher.dart';
import '../services/driver_mqtt_publisher.dart';
import '../services/driver_service.dart';
import '../services/transit_service.dart';
import '../utils/jwt.dart';

enum DriverShiftState { offShift, onShiftIdle, onShiftInTrip }

/// Brief §"What it means": "Driver has no assigned bus" / simulation-mode
/// markers surface via DriverApiException; we keep the latest as a UI cue.
class DriverProvider extends ChangeNotifier {
  final DriverService _service;
  final TransitService _transit;
  late final DriverMqttPublisher _mqtt;
  late final DriverLocationPublisher _locationPub;

  DriverProvider({DriverService? service, TransitService? transit})
    : _service = service ?? DriverService(),
      _transit = transit ?? TransitService() {
    _mqtt = DriverMqttPublisher(onAuthFailure: _onMqttAuthFailure);
    _locationPub = DriverLocationPublisher(publisher: _mqtt);
  }

  // ---- public state ----
  DriverProfile? _profile;
  DriverProfile? get profile => _profile;

  DriverShiftState _shiftState = DriverShiftState.offShift;
  DriverShiftState get shiftState => _shiftState;

  Trip? _activeTrip;
  Trip? get activeTrip => _activeTrip;

  /// Trips on the driver's assigned bus, pre-split by the backend.
  List<Trip> _today = const [];
  List<Trip> _history = const [];
  List<Trip> get today => _today;
  List<Trip> get history => _history;
  List<Trip> get allTrips => [..._today, ..._history];

  /// routeId → route metadata, so we can show code/name for trips whose
  /// `route` came back as a bare id (the `/drivers/me/trips` payload does not
  /// populate it). Filled once from the rider-facing routes endpoint.
  final Map<String, TransitRoute> _routes = {};

  /// Human-readable route title for a trip ("code name"), resolved from the
  /// route cache, falling back to whatever the trip payload carried.
  String routeTitle(Trip t) {
    final r = _routes[t.routeId];
    final code = r?.code ?? (t.routeNumber == '??' ? null : t.routeNumber);
    final name = r?.name ?? t.routeName;
    final label = [
      code,
      name,
    ].where((e) => e != null && e.isNotEmpty).join(' ');
    return label.isEmpty ? 'ដំណើរ' : label;
  }

  /// Bus number for a trip. Every trip is on the driver's assigned bus, so we
  /// fall back to the profile's bus when the trip payload didn't populate it.
  String? busNumberOf(Trip t) {
    if (t.busNumber != null && t.busNumber != 'N/A') return t.busNumber;
    return _profile?.assignedBusNumber;
  }

  bool _loadingTrips = false;
  bool get loadingTrips => _loadingTrips;

  bool _hasLocationPermission = false;
  bool get hasLocationPermission => _hasLocationPermission;

  String? _lastError;
  String? get lastError => _lastError;

  bool _busy = false;
  bool get busy => _busy;

  static const _credsKey = 'driver_mqtt_creds';

  // ---- lifecycle ----

  /// Call after a successful login when role === 'driver'.
  Future<void> init() async {
    await refreshProfile();
    await loadCachedCredentials();
    await checkLocationPermission();
    await _loadRoutes();
    await refreshTrips();
  }

  /// Populate the routeId → metadata cache from the rider routes endpoint so
  /// trip cards can show real names even when the trip payload has bare ids.
  Future<void> _loadRoutes() async {
    if (_routes.isNotEmpty) return;
    try {
      final routes = await _transit.fetchLineRoutes();
      for (final r in routes) {
        _routes[r.id] = r;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('DriverProvider: route metadata load failed: $e');
    }
  }

  Future<void> refreshProfile() async {
    // GET /drivers/me carries the live assignedBus. Falls back to JWT claims
    // only if the call fails (e.g. transient network error), so the shell
    // still shows the driver's name.
    try {
      _profile = await _service.fetchProfile();
      notifyListeners();
      return;
    } on DriverApiException catch (e) {
      debugPrint(
        'DriverProvider: /drivers/me failed (${e.statusCode}); '
        'falling back to JWT claims.',
      );
    }
    await _profileFromToken();
  }

  Future<void> _profileFromToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    final claims = decodeJwtPayload(token);
    debugPrint('DriverProvider: JWT claims = $claims');
    if (claims == null) return;
    _profile = DriverProfile(
      id: (claims['sub'] ?? claims['_id'] ?? claims['userId'] ?? '') as String,
      name: (claims['name'] ?? 'Driver') as String,
      role: (claims['role'] ?? 'driver') as String,
      assignedBusId: assignedBusFromToken(token),
    );
    if (!_profile!.hasAssignedBus) {
      debugPrint(
        'DriverProvider: assignedBus not present in JWT; '
        'trip filtering needs a backend source.',
      );
    }
    notifyListeners();
  }

  Future<void> checkLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _hasLocationPermission = false;
      notifyListeners();
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    _hasLocationPermission =
        perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
    // NOTE: Android-only — for true background publishing we should require
    // LocationPermission.always; UI gates trip start on whileInUse for now.
    notifyListeners();
  }

  // ---- shift control ----

  Future<void> setShift(bool on) async {
    _busy = true;
    notifyListeners();
    try {
      await _service.setShiftStatus(on ? 'on' : 'off');
      if (on) {
        _shiftState = DriverShiftState.onShiftIdle;
        // Lazy-connect MQTT once on-shift so the publish loop has a live
        // session ready when a trip starts.
        await _ensureMqttReady();
      } else {
        // Going off-shift auto-cancels any in-progress trip server-side.
        await _stopPublishLoop();
        _activeTrip = null;
        _shiftState = DriverShiftState.offShift;
      }
      _lastError = null;
    } on DriverApiException catch (e) {
      _lastError = e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  // ---- trips ----

  Future<void> refreshTrips() async {
    _loadingTrips = true;
    notifyListeners();
    try {
      final result = await _service.fetchMyTrips();
      _today = result.today;
      _history = result.history;
      // The trips endpoint is authoritative for the live bus assignment;
      // backfill the profile if it didn't carry one.
      if (result.assignedBusId != null &&
          _profile != null &&
          !_profile!.hasAssignedBus) {
        _profile = DriverProfile(
          id: _profile!.id,
          name: _profile!.name,
          role: _profile!.role,
          assignedBusId: result.assignedBusId,
        );
      }
      // Sync the active trip from server-side truth.
      final inProgress = allTrips.where((t) => t.isInProgress).toList();
      if (inProgress.isNotEmpty) {
        _activeTrip = inProgress.first;
        _shiftState = DriverShiftState.onShiftInTrip;
        await _ensureMqttReady();
        await _startPublishLoop();
      } else if (_shiftState == DriverShiftState.onShiftInTrip) {
        // The server moved us out of in-progress (completion/cancellation).
        _activeTrip = null;
        _shiftState = DriverShiftState.onShiftIdle;
        await _stopPublishLoop();
      }
      _lastError = null;
    } on DriverApiException catch (e) {
      _lastError = e.message;
    } finally {
      _loadingTrips = false;
      notifyListeners();
    }
  }

  Future<bool> startTrip(String tripId) async {
    if (!_hasLocationPermission) {
      _lastError = 'Location permission required to start a trip.';
      notifyListeners();
      return false;
    }
    _busy = true;
    notifyListeners();
    try {
      final trip = await _service.startTrip(tripId);
      _activeTrip = trip;
      _shiftState = DriverShiftState.onShiftInTrip;
      await _ensureMqttReady();
      await _startPublishLoop();
      await refreshTrips();
      _lastError = null;
      return true;
    } on DriverApiException catch (e) {
      _lastError = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancelTrip() async {
    _busy = true;
    notifyListeners();
    try {
      await _service.cancelCurrentTrip();
      await _stopPublishLoop();
      _activeTrip = null;
      _shiftState = DriverShiftState.onShiftIdle;
      await refreshTrips();
      _lastError = null;
      return true;
    } on DriverApiException catch (e) {
      _lastError = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Route polyline source — reuses the same endpoint riders use to draw
  /// the route so visuals match between rider/driver apps.
  Future<List<RouteStop>> fetchActiveRouteStops() async {
    final routeId = _activeTrip?.routeId;
    if (routeId == null) return const [];
    try {
      return await _transit.fetchRouteStops(routeId);
    } catch (e) {
      debugPrint('DriverProvider: fetchActiveRouteStops failed: $e');
      return const [];
    }
  }

  // ---- MQTT plumbing ----

  Future<void> _ensureMqttReady() async {
    if (_mqtt.isConnected) return;
    var creds = await _loadCachedCreds();
    creds ??= await _fetchAndCacheCreds();
    if (creds == null) return;
    try {
      await _mqtt.connect(creds);
    } on DriverMqttAuthFailure {
      // Rotate creds once and try again.
      final fresh = await _fetchAndCacheCreds();
      if (fresh != null) {
        try {
          await _mqtt.connect(fresh);
        } catch (e) {
          debugPrint(
            'DriverProvider: MQTT reconnect after rotation failed: $e',
          );
        }
      }
    }
  }

  Future<DriverMqttCredentials?> _fetchAndCacheCreds() async {
    try {
      final c = await _service.fetchMqttCredentials();
      final prefs = await SharedPreferences.getInstance();
      // NOTE: shared_preferences is plaintext. The brief asks for
      // Keychain/Keystore — flagged as a hardening follow-up.
      await prefs.setString(_credsKey, jsonEncode(c.toJson()));
      return c;
    } on DriverApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<DriverMqttCredentials?> _loadCachedCreds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_credsKey);
    if (raw == null) return null;
    try {
      return DriverMqttCredentials.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> loadCachedCredentials() async {
    await _loadCachedCreds();
  }

  void _onMqttAuthFailure() {
    // Fired from inside the publisher's connect path; defer the credential
    // rotation so we don't re-enter connect synchronously.
    Future.microtask(() async {
      debugPrint('DriverProvider: rotating MQTT creds after auth failure');
      await _fetchAndCacheCreds();
    });
  }

  Future<void> _startPublishLoop() async {
    if (!_hasLocationPermission) return;
    if (!_mqtt.isConnected) return;
    await _locationPub.start();
  }

  Future<void> _stopPublishLoop() async {
    await _locationPub.stop();
  }

  Future<void> shutdownForLogout() async {
    await _stopPublishLoop();
    await _mqtt.disconnect();
    _profile = null;
    _activeTrip = null;
    _today = const [];
    _history = const [];
    _shiftState = DriverShiftState.offShift;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationPub.stop();
    _mqtt.disconnect();
    super.dispose();
  }
}

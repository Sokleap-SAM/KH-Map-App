import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';
import '../models/route_plan.dart';
import '../models/route_search_selection.dart';
import '../services/location_service.dart';
import '../services/place_service.dart';
import '../services/transit_service.dart';

class MapProvider extends ChangeNotifier {
  final LocationService _locationService;
  final TransitService _transitService = TransitService();
  final PlaceService _placeService = PlaceService();

  MapProvider(this._locationService);

  // ── Location ──────────────────────────────────────────────────────────────
  LatLng? _currentPosition;
  bool _locationError = false;
  bool _followUser = true;
  StreamSubscription<LatLng>? _positionSub;

  LatLng? get currentPosition => _currentPosition;
  bool get locationError => _locationError;
  bool get followUser => _followUser;

  // ── Places ────────────────────────────────────────────────────────────────
  List<Place> _places = [];
  bool _placesLoading = true;
  String? _placesError;

  List<Place> get places => _places;
  bool get placesLoading => _placesLoading;
  String? get placesError => _placesError;

  // Dropped pin state
  LatLng? _droppedPin;
  String? _droppedPinPlace;
  String? _droppedPinRoad;
  bool _isLoadingPinInfo = false;

  LatLng? get droppedPin => _droppedPin;
  String? get droppedPinPlace => _droppedPinPlace;
  String? get droppedPinRoad => _droppedPinRoad;
  bool get isLoadingPinInfo => _isLoadingPinInfo;

  // ── Route search overlay ─────────────────────────────────────────────────
  bool _showRouteSearch = false;
  RouteSearchSelection? _routeSearchDestination;
  bool _isMapPickMode = false;
  void Function(RouteSearchSelection)? _mapPickCallback;

  bool get showRouteSearch => _showRouteSearch;
  RouteSearchSelection? get routeSearchDestination => _routeSearchDestination;
  bool get isMapPickMode => _isMapPickMode;

  // ── Routing state (State A → B → C per ROUTING.md) ───────────────────────
  bool _showBusLines = true;
  bool _isRoutingActive = false;
  bool _isLoadingRoute = false;
  String? _routeError;
  RoutePlanResult? _routePlan;

  int _activeOptionIndex = 0;
  String _planType = 'transit'; // "walk" | "transit"
  LatLng? _routingDestination;
  LatLng? _routingOrigin;
  bool _useLiveCurrentOrigin = true;

  Timer? _routePollTimer;
  bool _refreshInProgress = false;
  static const Duration _pollInterval = Duration(seconds: 5);

  bool get showBusLines => _showBusLines;
  bool get isRoutingActive => _isRoutingActive;
  bool get isLoadingRoute => _isLoadingRoute;
  String? get routeError => _routeError;
  RoutePlanResult? get routePlan => _routePlan;
  int get activeOptionIndex => _activeOptionIndex;
  String get planType => _planType;

  // ── Recent Searches ───────────────────────────────────────────────────────
  final List<String> _recentSearchIds = [];
  List<String> get recentSearchIds => _recentSearchIds;

  RouteOption? get activeOption {
    final plan = _routePlan;
    if (plan == null || !plan.found || plan.options.isEmpty) return null;
    final idx = _activeOptionIndex.clamp(0, plan.options.length - 1);
    return plan.options[idx];
  }

  // ── Initialization & Core Setup ───────────────────────────────────────────

  Future<void> init() async {
    final initial = await _locationService.getCurrentPosition();
    if (initial == null) {
      _locationError = true;
      notifyListeners();
      return;
    }
    _currentPosition = initial;
    notifyListeners();

    _positionSub = _locationService.positionStream.listen((latLng) {
      _currentPosition = latLng;
      notifyListeners();
    });
    await _loadRecentSearches();

    await loadPlaces();
  }

  Future<void> loadPlaces() async {
    _placesLoading = true;
    _placesError = null;
    notifyListeners();
    try {
      _places = await _placeService.fetchPlaces();
    } catch (e) {
      _placesError = e.toString();
      debugPrint('MapProvider: failed to load places: $e');
    } finally {
      _placesLoading = false;
      notifyListeners();
    }
  }

  void setFollowUser(bool value) {
    if (_followUser == value) return;
    _followUser = value;
    notifyListeners();
  }

  // ── Pins Management ───────────────────────────────────────────────────────

  Future<void> dropPin(LatLng position) async {
    _droppedPin = position;
    _droppedPinPlace = null;
    _droppedPinRoad = null;
    _isLoadingPinInfo = true;
    notifyListeners();

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${position.latitude}&lon=${position.longitude}'
        '&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'kh_map_app/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _droppedPinPlace = data['display_name'];
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          _droppedPinRoad =
              address['road'] ?? address['pedestrian'] ?? address['footway'];
        }
      }
    } catch (e) {
      debugPrint('MapProvider: Reverse geocoding failed: $e');
    } finally {
      _isLoadingPinInfo = false;
      notifyListeners();
    }
  }

  void removePin() {
    _droppedPin = null;
    _droppedPinPlace = null;
    _droppedPinRoad = null;
    _isLoadingPinInfo = false;
    notifyListeners();
  }

  // ── Route Search Overlay & Map Pick ───────────────────────────────────────

  void openRouteSearch(RouteSearchSelection destination) {
    _routeSearchDestination = destination;
    _showRouteSearch = true;
    notifyListeners();
  }

  void closeRouteSearch() {
    _showRouteSearch = false;
    _routeSearchDestination = null;
    _isMapPickMode = false;
    _mapPickCallback = null;
    notifyListeners();
  }

  void startMapPick(void Function(RouteSearchSelection) onPicked) {
    _mapPickCallback = onPicked;
    _isMapPickMode = true;
    notifyListeners();
  }

  void cancelMapPick() {
    _mapPickCallback = null;
    _isMapPickMode = false;
    notifyListeners();
  }

  Future<void> handleMapPickTap(LatLng latLng) async {
    if (!_isMapPickMode || _mapPickCallback == null) return;
    final cb = _mapPickCallback!;
    _isMapPickMode = false;
    _mapPickCallback = null;
    notifyListeners();

    String label =
        '${latLng.latitude.toStringAsFixed(6)}, ${latLng.longitude.toStringAsFixed(6)}';
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}'
        '&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'kh_map_app/1.0'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          label = displayName.split(',').first.trim();
        }
      }
    } catch (_) {}

    cb(RouteSearchSelection(label: label, location: latLng));
  }

  Future<void> submitRouteSearch({
    required RouteSearchSelection origin,
    required RouteSearchSelection destination,
  }) async {
    await setPlanType('transit');
    await startRoutingFrom(
      origin: origin.location,
      destination: destination.location,
      useLiveCurrentOrigin: origin.useLiveCurrentLocation,
    );
  }

  // ── Routing Logic & State Management ──────────────────────────────────────

  void setActiveOptionIndex(int index) {
    if (_routePlan == null) return;
    final clamped = index.clamp(0, _routePlan!.options.length - 1);
    if (_activeOptionIndex == clamped) return;
    _activeOptionIndex = clamped;
    notifyListeners();
  }

  Future<void> setPlanType(String type) async {
    if (_planType == type) return;
    _planType = type;
    notifyListeners();
    if (_isRoutingActive && _routingDestination != null) {
      final origin = _activeOriginForQuery();
      if (origin == null) return;
      _stopPollTimer();
      await _fetchRoutePlan(origin: origin, destination: _routingDestination!);
      _startPollTimer();
    }
  }

  Future<void> startRouting(LatLng destination) async {
    await startRoutingFrom(origin: _currentPosition, destination: destination);
  }

  Future<void> startRoutingFrom({
    required LatLng? origin,
    required LatLng destination,
    bool useLiveCurrentOrigin = false,
  }) async {
    final resolvedOrigin = useLiveCurrentOrigin ? _currentPosition : origin;
    if (resolvedOrigin == null) return;
    _routingOrigin = resolvedOrigin;
    _useLiveCurrentOrigin = useLiveCurrentOrigin;
    _routingDestination = destination;
    _showBusLines = false;
    _isRoutingActive = true;
    _stopPollTimer();
    await _fetchRoutePlan(origin: resolvedOrigin, destination: destination);
    _startPollTimer();
  }

  void _startPollTimer() {
    _routePollTimer?.cancel();
    if (_isRoutingActive) {
      _routePollTimer = Timer(_pollInterval, _scheduledRefresh);
    }
  }

  void _stopPollTimer() {
    _routePollTimer?.cancel();
    _routePollTimer = null;
  }

  Future<void> _scheduledRefresh() async {
    if (!_isRoutingActive) return;
    await _silentRefresh();
    // Re-verify routing flag after network delay to ensure it wasn't cancelled mid-flight
    if (_isRoutingActive) {
      _routePollTimer = Timer(_pollInterval, _scheduledRefresh);
    }
  }

  Future<void> _silentRefresh() async {
    if (_refreshInProgress) return;
    final dest = _routingDestination;
    final origin = _activeOriginForQuery();
    if (dest == null || origin == null || !_isRoutingActive) return;

    _refreshInProgress = true;
    try {
      final plan = await _transitService.fetchRoutePlan(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
        type: _planType,
      );
      if (_isRoutingActive) {
        _routePlan = plan;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('MapProvider: silent refresh failed: $e');
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _fetchRoutePlan({
    required LatLng origin,
    required LatLng destination,
  }) async {
    _isLoadingRoute = true;
    _routeError = null;
    _routePlan = null;
    _activeOptionIndex = 0;
    notifyListeners();

    try {
      final plan = await _transitService.fetchRoutePlan(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: destination.latitude,
        destLng: destination.longitude,
        type: _planType,
      );
      _routePlan = plan;
    } catch (e) {
      _routeError = e.toString();
      debugPrint('MapProvider: routing failed: $e');
    } finally {
      _isLoadingRoute = false;
      notifyListeners();
    }
  }

  void clearRouting() {
    _stopPollTimer();
    _showBusLines = true;
    _isRoutingActive = false;
    _isLoadingRoute = false;
    _routeError = null;
    _routePlan = null;
    _activeOptionIndex = 0;
    _routingOrigin = null;
    _routingDestination = null;
    _useLiveCurrentOrigin = true;
    notifyListeners();
  }

  LatLng? _activeOriginForQuery() {
    return _useLiveCurrentOrigin ? _currentPosition : _routingOrigin;
  }

  // ── Recent Searches Logic ──────────────────────────────────────────────────

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? savedIds = prefs.getStringList('recent_searches');
      if (savedIds != null) {
        _recentSearchIds.clear();
        _recentSearchIds.addAll(savedIds);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('MapProvider: Failed to load recent searches: $e');
    }
  }

  Future<void> addToRecentSearches(String placeId) async {
    // Remove if exists to avoid duplicates, then insert at top
    _recentSearchIds.remove(placeId);
    _recentSearchIds.insert(0, placeId);

    // Limit to 5 items
    if (_recentSearchIds.length > 5) {
      _recentSearchIds.removeLast();
    }

    notifyListeners();

    // Persist to disk
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('recent_searches', _recentSearchIds);
    } catch (e) {
      debugPrint('MapProvider: Failed to save recent searches: $e');
    }
  }

  Future<void> clearRecentSearches() async {
    _recentSearchIds.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_searches');
  }

  @override
  void dispose() {
    _stopPollTimer();
    _positionSub?.cancel();
    super.dispose();
  }
}

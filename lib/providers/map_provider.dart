import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

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

  // ── Places ────────────────────────────────────────────────────────────────
  List<Place> _places = [];
  bool _placesLoading = true;
  String? _placesError;

  List<Place> get places => _places;
  bool get placesLoading => _placesLoading;
  String? get placesError => _placesError;

  // ── Category filter ──────────────────────────────────────────────────────
  // When the user taps a category icon under the search bar, we show every
  // place of that category on the map (sorted nearest-first when the user's
  // location is known).
  static const Distance _distance = Distance();

  String? _activeCategoryKey;
  List<String> _categoryKeywords = const [];
  List<Place> _nearbyCategoryPlaces = [];

  /// Identifier of the active category button (e.g. 'restaurant'), or null.
  String? get activeCategoryKey => _activeCategoryKey;
  bool get hasCategoryFilter => _activeCategoryKey != null;

  /// Matching places for the active category, nearest first.
  List<Place> get nearbyCategoryPlaces => _nearbyCategoryPlaces;

  /// Places to draw on the map: only the category matches while a filter is
  /// active, otherwise every loaded place.
  List<Place> get displayPlaces =>
      _activeCategoryKey != null ? _nearbyCategoryPlaces : _places;

  /// Toggles the filter for a category. Tapping the active category again
  /// clears it. Returns the resulting matches (empty when cleared).
  List<Place> toggleCategoryFilter({
    required String key,
    required List<String> keywords,
  }) {
    if (_activeCategoryKey == key) {
      clearCategoryFilter();
      return const [];
    }
    _activeCategoryKey = key;
    _categoryKeywords = keywords.map((k) => k.toLowerCase()).toList();
    _recomputeNearbyCategory();
    notifyListeners();
    return _nearbyCategoryPlaces;
  }

  void clearCategoryFilter() {
    if (_activeCategoryKey == null) return;
    _activeCategoryKey = null;
    _categoryKeywords = const [];
    _nearbyCategoryPlaces = const [];
    notifyListeners();
  }

  void _recomputeNearbyCategory() {
    if (_activeCategoryKey == null) {
      _nearbyCategoryPlaces = const [];
      return;
    }
    final matches = <Place>[];
    for (final p in _places) {
      final name = p.category?.name.toLowerCase() ?? '';
      if (name.isEmpty) continue;
      if (_categoryKeywords.any(name.contains)) matches.add(p);
    }
    // Sort nearest-first when we know where the user is.
    final origin = _currentPosition;
    if (origin != null) {
      matches.sort((a, b) {
        final da = _distance.as(
          LengthUnit.Meter,
          origin,
          LatLng(a.latitude, a.longitude),
        );
        final db = _distance.as(
          LengthUnit.Meter,
          origin,
          LatLng(b.latitude, b.longitude),
        );
        return da.compareTo(db);
      });
    }
    _nearbyCategoryPlaces = matches;
  }

  // Dropped pin state
  LatLng? _droppedPin;
  String? _droppedPinPlace;
  String? _droppedPinRoad;
  bool _isLoadingPinInfo = false;

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

  /// Index of the currently selected route option (0 = fastest by default).
  int _activeOptionIndex = 0;

  /// The plan mode: "walk" | "transit" (default: transit).
  String _planType = 'transit';

  /// Last destination passed to [startRouting]; used when [setPlanType] triggers a re-fetch.
  LatLng? _routingDestination;
  LatLng? _routingOrigin;
  bool _useLiveCurrentOrigin = true;

  /// Polls the route plan every 5 s while routing is active.
  Timer? _routePollTimer;
  bool _refreshInProgress = false;
  static const Duration _pollInterval = Duration(seconds: 5);

  LatLng? get currentPosition => _currentPosition;
  bool get locationError => _locationError;
  bool get followUser => _followUser;
  LatLng? get droppedPin => _droppedPin;
  String? get droppedPinPlace => _droppedPinPlace;
  String? get droppedPinRoad => _droppedPinRoad;
  bool get isLoadingPinInfo => _isLoadingPinInfo;
  bool get showBusLines => _showBusLines;
  bool get isRoutingActive => _isRoutingActive;
  bool get isLoadingRoute => _isLoadingRoute;
  String? get routeError => _routeError;
  RoutePlanResult? get routePlan => _routePlan;
  int get activeOptionIndex => _activeOptionIndex;
  String get planType => _planType;

  /// The currently selected [RouteOption], or null when no route is loaded.
  RouteOption? get activeOption {
    final plan = _routePlan;
    if (plan == null || !plan.found || plan.options.isEmpty) return null;
    final idx = _activeOptionIndex.clamp(0, plan.options.length - 1);
    return plan.options[idx];
  }

  /// Switch the active route option tab without re-fetching.
  void setActiveOptionIndex(int index) {
    if (_routePlan == null) return;
    final clamped = index.clamp(0, _routePlan!.options.length - 1);
    if (_activeOptionIndex == clamped) return;
    _activeOptionIndex = clamped;
    notifyListeners();
  }

  /// Switch between "walk" and "transit" plans.
  /// Re-fetches immediately if routing is already active.
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
      if (_activeCategoryKey != null) _recomputeNearbyCategory();
      notifyListeners();
    });
    // Load places after location is known.
    await loadPlaces();
  }

  Future<void> loadPlaces() async {
    _placesLoading = true;
    _placesError = null;
    notifyListeners();
    try {
      _places = await _placeService.fetchPlaces();
      if (_activeCategoryKey != null) _recomputeNearbyCategory();
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
    } catch (_) {
      // Reverse geocoding failed — coordinates will still display
    }

    _isLoadingPinInfo = false;
    notifyListeners();
  }

  void removePin() {
    _droppedPin = null;
    _droppedPinPlace = null;
    _droppedPinRoad = null;
    _isLoadingPinInfo = false;
    notifyListeners();
  }

  // ── Route search overlay ──────────────────────────────────────────────────

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

  /// Reverse-geocodes [latLng] and fires the pending map-pick callback.
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

  /// Submits the route search: sets plan type to transit and starts routing.
  /// The overlay stays visible until the user dismisses the route card.
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

  /// Transitions to State C: hides bus lines, fetches the route plan,
  /// then starts polling every 5 s for live-ETA updates.
  Future<void> startRouting(LatLng destination) async {
    await startRoutingFrom(origin: _currentPosition, destination: destination);
  }

  /// Starts routing from a specific [origin] to [destination].
  ///
  /// Set [useLiveCurrentOrigin] to true to keep refreshing with the user's
  /// current location during polling; otherwise the chosen origin is fixed.
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
    _routePollTimer = Timer(_pollInterval, _scheduledRefresh);
  }

  void _stopPollTimer() {
    _routePollTimer?.cancel();
    _routePollTimer = null;
  }

  /// Called by the timer — runs a silent refresh then reschedules itself.
  /// Uses a single-shot Timer (not periodic) so a slow response can never
  /// cause concurrent requests to pile up and overload the backend.
  Future<void> _scheduledRefresh() async {
    await _silentRefresh();
    // Only reschedule if routing is still active (timer may have been
    // cancelled by clearRouting / setPlanType while we were awaiting).
    if (_isRoutingActive && _routePollTimer != null) {
      _routePollTimer = Timer(_pollInterval, _scheduledRefresh);
    }
  }

  /// Re-fetches the active route plan without resetting [_routePlan] or
  /// showing the loading indicator — so the UI updates smoothly.
  Future<void> _silentRefresh() async {
    if (_refreshInProgress) return; // guard against overlap
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
      _routePlan = plan;
      notifyListeners();
    } catch (e) {
      // Silent — keep showing the last good result.
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

  /// Returns to State A: shows bus lines, clears routing overlay.
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
    if (_useLiveCurrentOrigin) return _currentPosition;
    return _routingOrigin;
  }

  @override
  void dispose() {
    _stopPollTimer();
    _positionSub?.cancel();
    super.dispose();
  }
}

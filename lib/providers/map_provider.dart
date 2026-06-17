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

  LatLng? get droppedPin => _droppedPin;
  String? get droppedPinPlace => _droppedPinPlace;
  String? get droppedPinRoad => _droppedPinRoad;
  bool get isLoadingPinInfo => _isLoadingPinInfo;

  // ── Route search overlay ─────────────────────────────────────────────────
  bool _showRouteSearch = false;
  RouteSearchSelection? _routeSearchDestination;

  /// Pre-filled origin for the overlay. Null in the normal flow (the overlay
  /// defaults the origin to the user's live location); set when opening a saved
  /// favorite route so its fixed origin is shown instead.
  RouteSearchSelection? _routeSearchOrigin;
  bool _isMapPickMode = false;
  void Function(RouteSearchSelection)? _mapPickCallback;

  /// One-shot camera target consumed by the map screen — e.g. to frame a
  /// favorite route's origin when it's opened from another tab.
  LatLng? _cameraMoveTarget;

  /// Live preview of the origin/destination chosen in the route search overlay.
  /// Rendered on the map as numbered pins (1 = origin, 2 = destination) so the
  /// user can see what they've selected before submitting the route.
  LatLng? _routeSearchOriginPin;
  LatLng? _routeSearchDestinationPin;

  bool get showRouteSearch => _showRouteSearch;
  RouteSearchSelection? get routeSearchDestination => _routeSearchDestination;
  RouteSearchSelection? get routeSearchOrigin => _routeSearchOrigin;
  LatLng? get cameraMoveTarget => _cameraMoveTarget;
  bool get isMapPickMode => _isMapPickMode;
  LatLng? get routeSearchOriginPin => _routeSearchOriginPin;
  LatLng? get routeSearchDestinationPin => _routeSearchDestinationPin;

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
  String? _routingOriginLabel;
  String? _routingDestinationLabel;
  bool _useLiveCurrentOrigin = true;

  Timer? _routePollTimer;
  bool _refreshInProgress = false;
  static const Duration _pollInterval = Duration(seconds: 5);

  /// When non-null, the route info card is showing a saved favorite route, so
  /// the bookmark icon renders as already-saved. The route itself is re-planned
  /// through the normal `/transit/plan` flow (which polls for live ETAs).
  String? _activeFavoriteId;

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

  /// Origin/destination of the active routing flow, for persisting a favorite.
  LatLng? get routingOrigin => _routingOrigin;
  LatLng? get routingDestination => _routingDestination;
  String? get routingOriginLabel => _routingOriginLabel;
  String? get routingDestinationLabel => _routingDestinationLabel;

  /// True when the active route's origin tracks the user's live location (so a
  /// saved favorite should resolve a stable address instead of a "current
  /// location" label).
  bool get useLiveCurrentOrigin => _useLiveCurrentOrigin;

  /// Id of the saved favorite currently displayed, or null for a planned trip.
  String? get activeFavoriteId => _activeFavoriteId;

  /// The currently selected [RouteOption], or null when no route is loaded.
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
      if (_activeCategoryKey != null) _recomputeNearbyCategory();
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
        final String fullAddress = data['display_name'] ?? "";

        // Filter out segments that look like IDs or numbers (e.g. "12345678")
        final segments = fullAddress
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !RegExp(r'^\d+$').hasMatch(s))
            .toList();

        if (segments.isNotEmpty) {
          _droppedPinPlace = segments.first;
        } else {
          _droppedPinPlace = "Dropped Pin";
        }

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

  /// Reverse-geocodes [point] to a short human label (first address
  /// component), falling back to a `lat, lng` string when the lookup fails.
  /// Used when persisting a favorite route so a fixed saved origin isn't
  /// mislabelled "Current location" after the user moves.
  Future<String> reverseGeocodeLabel(LatLng point) async {
    final fallback =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${point.latitude}&lon=${point.longitude}'
        '&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'kh_map_app/1.0'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.trim().isNotEmpty) {
          return displayName.split(',').first.trim();
        }
      }
    } catch (_) {
      // Fall through to coordinate label.
    }
    return fallback;
  }

  // ── Route search overlay ──────────────────────────────────────────────────

  /// Consumed by the map screen after it moves the camera, so the move only
  /// happens once.
  void consumeCameraMoveTarget() {
    _cameraMoveTarget = null;
  }

  /// Displays a saved favorite route on the map: the overlay pre-filled with
  /// its fixed origin/destination, the route info card, and the drawn polyline
  /// — showing ONLY the saved [option] (already rebuilt with live ETAs by the
  /// backend's `/favorites/:id/live`). Unlike the normal flow it does NOT call
  /// `/transit/plan` (which returns several alternatives) and does not poll.
  void openFavoriteRoute({
    required String favoriteId,
    required RouteSearchSelection origin,
    required RouteSearchSelection destination,
  }) {
    // Overlay fields + preview pins.
    _routeSearchOrigin = origin;
    _routeSearchDestination = destination;
    _routeSearchOriginPin = origin.location;
    _routeSearchDestinationPin = destination.location;
    _showRouteSearch = true;

    // Camera: frame the origin once.
    _followUser = false;
    _cameraMoveTarget = origin.location;

    // Mark which favorite this is so the route info card shows it as saved.
    // Set AFTER routing kicks off because _fetchRoutePlan no longer clears it.
    _activeFavoriteId = favoriteId;
    _planType = 'transit';
    notifyListeners();
    // Re-plan from the saved endpoints through the normal flow (route card,
    // polyline, live 5 s poll). The favorite stores only origin/destination.
    startRoutingFrom(
      origin: origin.location,
      destination: destination.location,
      originLabel: origin.label,
      destinationLabel: destination.label,
    );
  }

  /// Clears the active-favorite marker (e.g. after the user removes it from the
  /// route info card) so the bookmark icon stops showing as saved.
  void clearActiveFavoriteId() {
    if (_activeFavoriteId == null) return;
    _activeFavoriteId = null;
    notifyListeners();
  }

  void openRouteSearch(RouteSearchSelection destination) {
    _routeSearchDestination = destination;
    _routeSearchOrigin = null;
    _activeFavoriteId = null;
    _routeSearchDestinationPin = destination.location;
    // Default origin is the user's current location; the overlay overrides
    // this via [updateRouteSearchPins] if the user picks a different origin.
    _routeSearchOriginPin = _currentPosition;
    _showRouteSearch = true;
    notifyListeners();
    // Auto-fetch the plan immediately so the route info card streams in
    // without the user having to hit a "Go" button.
    final origin = _currentPosition;
    if (origin != null) {
      submitRouteSearch(
        origin: RouteSearchSelection(
          label: 'Current location',
          location: origin,
          useLiveCurrentLocation: true,
        ),
        destination: destination,
      );
    }
  }

  /// Updates the live origin/destination preview pins. Called by the route
  /// search overlay whenever either field changes (search-screen pick,
  /// map-pick, or reset-to-current-location).
  void updateRouteSearchPins({LatLng? origin, LatLng? destination}) {
    if (_routeSearchOriginPin == origin &&
        _routeSearchDestinationPin == destination) {
      return;
    }
    _routeSearchOriginPin = origin;
    _routeSearchDestinationPin = destination;
    notifyListeners();
  }

  void closeRouteSearch() {
    _showRouteSearch = false;
    _routeSearchDestination = null;
    _routeSearchOrigin = null;
    _routeSearchOriginPin = null;
    _routeSearchDestinationPin = null;
    _routeSearchOrigin = null;
    _routeSearchOriginPin = null;
    _routeSearchDestinationPin = null;
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

    // Use a friendly label for map picks instead of raw coordinate "IDs"
    String label =
        'Point (${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)})';
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
    // A user-driven search (or overlay edit) is no longer a saved favorite.
    _activeFavoriteId = null;
    await setPlanType('transit');
    await startRoutingFrom(
      origin: origin.location,
      destination: destination.location,
      useLiveCurrentOrigin: origin.useLiveCurrentLocation,
      originLabel: origin.label,
      destinationLabel: destination.label,
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
    String? originLabel,
    String? destinationLabel,
  }) async {
    final resolvedOrigin = useLiveCurrentOrigin ? _currentPosition : origin;
    if (resolvedOrigin == null) return;
    _routingOrigin = resolvedOrigin;
    _useLiveCurrentOrigin = useLiveCurrentOrigin;
    _routingDestination = destination;
    _routingOriginLabel = originLabel;
    _routingDestinationLabel = destinationLabel;
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
    // A real /plan fetch means we're no longer showing a saved favorite.
    _activeFavoriteId = null;
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
    _activeFavoriteId = null;
    _showBusLines = true;
    _isRoutingActive = false;
    _isLoadingRoute = false;
    _routeError = null;
    _routePlan = null;
    _activeOptionIndex = 0;
    _routingOrigin = null;
    _routingDestination = null;
    _routingOriginLabel = null;
    _routingDestinationLabel = null;
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

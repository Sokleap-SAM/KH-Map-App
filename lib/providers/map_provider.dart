import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/place.dart';
import '../models/route_plan.dart';
import '../models/route_search_selection.dart';
import '../services/favorite_routes_service.dart';
import '../services/location_service.dart';
import '../services/place_service.dart';
import '../services/transit_service.dart';

class MapProvider extends ChangeNotifier {
  final LocationService _locationService;
  final TransitService _transitService = TransitService();
  final PlaceService _placeService = PlaceService();
  final FavoriteRoutesService _favoriteRoutesService = FavoriteRoutesService();

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

  // Dropped pin state
  LatLng? _droppedPin;
  String? _droppedPinPlace;
  String? _droppedPinRoad;
  bool _isLoadingPinInfo = false;

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

  /// Index of the currently selected route option (0 = fastest by default).
  int _activeOptionIndex = 0;

  /// The plan mode: "walk" | "transit" (default: transit).
  String _planType = 'transit';

  /// Last destination passed to [startRouting]; used when [setPlanType] triggers a re-fetch.
  LatLng? _routingDestination;
  LatLng? _routingOrigin;
  String? _routingOriginLabel;
  String? _routingDestinationLabel;
  bool _useLiveCurrentOrigin = true;

  /// Polls the route plan every 5 s while routing is active.
  Timer? _routePollTimer;
  bool _refreshInProgress = false;
  static const Duration _pollInterval = Duration(seconds: 5);

  /// When non-null, the route info card is showing a saved favorite route (not
  /// a freshly-planned trip). Drives the filled bookmark state and the
  /// favorite-live poll instead of the `/transit/plan` poll.
  String? _activeFavoriteId;
  Timer? _favoritePollTimer;

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
  void showFavoriteRoute({
    required String favoriteId,
    required RouteSearchSelection origin,
    required RouteSearchSelection destination,
    required RouteOption option,
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

    // Routing state — a single fixed option from the saved favorite.
    _stopPollTimer();
    _activeFavoriteId = favoriteId;
    _routingOrigin = origin.location;
    _routingDestination = destination.location;
    _useLiveCurrentOrigin = false;
    _planType = 'transit';
    _showBusLines = false;
    _isRoutingActive = true;
    _isLoadingRoute = false;
    _routeError = null;
    _activeOptionIndex = 0;
    _routePlan = RoutePlanResult(
      found: true,
      type: 'transit',
      options: [option],
    );
    notifyListeners();
    // Refresh ETAs from /favorites/:id/live on the same cadence as the plan
    // poll, so the saved route's bus times stay live without re-planning.
    _startFavoritePoll();
  }

  /// Clears the active-favorite marker (e.g. after the user removes it from the
  /// route info card) so the bookmark icon stops showing as saved.
  void clearActiveFavoriteId() {
    if (_activeFavoriteId == null) return;
    _activeFavoriteId = null;
    _stopFavoritePoll();
    notifyListeners();
  }

  void _startFavoritePoll() {
    _favoritePollTimer?.cancel();
    _favoritePollTimer = Timer(_pollInterval, _scheduledFavoriteRefresh);
  }

  void _stopFavoritePoll() {
    _favoritePollTimer?.cancel();
    _favoritePollTimer = null;
  }

  Future<void> _scheduledFavoriteRefresh() async {
    await _silentFavoriteRefresh();
    if (_isRoutingActive &&
        _activeFavoriteId != null &&
        _favoritePollTimer != null) {
      _favoritePollTimer = Timer(_pollInterval, _scheduledFavoriteRefresh);
    }
  }

  /// Re-fetches the saved favorite's live option and swaps it in without a
  /// loading flicker. Keeps the last good result on failure.
  Future<void> _silentFavoriteRefresh() async {
    final id = _activeFavoriteId;
    if (id == null || !_isRoutingActive || _refreshInProgress) return;
    _refreshInProgress = true;
    try {
      final live = await _favoriteRoutesService.fetchLive(id);
      _routePlan = RoutePlanResult(
        found: true,
        type: 'transit',
        options: [live.option],
      );
      notifyListeners();
    } catch (e) {
      debugPrint('MapProvider: favorite refresh failed: $e');
    } finally {
      _refreshInProgress = false;
    }
  }

  void openRouteSearch(RouteSearchSelection destination) {
    _routeSearchDestination = destination;
    _routeSearchOrigin = null;
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
      originLabel: origin.label,
      destinationLabel: destination.label,
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
    // A real /plan fetch means we're no longer showing a saved favorite.
    _activeFavoriteId = null;
    _stopFavoritePoll();
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
    _stopFavoritePoll();
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
    if (_useLiveCurrentOrigin) return _currentPosition;
    return _routingOrigin;
  }

  @override
  void dispose() {
    _stopPollTimer();
    _stopFavoritePoll();
    _positionSub?.cancel();
    super.dispose();
  }
}

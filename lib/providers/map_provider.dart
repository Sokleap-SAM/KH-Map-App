import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';
import '../models/route_plan.dart';
import '../models/route_progress.dart';
import '../models/route_search_selection.dart';
import '../models/trip.dart';
import '../models/trip_eta.dart';
import '../services/location_service.dart';
import '../services/place_service.dart';
import '../services/transit_service.dart';
import '../utils/path_progress.dart';

/// Why a route-plan request failed — mapped to a friendly, localized message
/// in the UI rather than surfacing a raw exception string to the user.
enum RoutePlanError { timeout, offline, generic }

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

  /// When true, real GPS fixes are ignored and [_currentPosition] is driven by
  /// [setSimulatedPosition] — a testing aid for the route planner.
  bool _simulatingLocation = false;
  bool get isSimulatingLocation => _simulatingLocation;

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
  RoutePlanError? _routeError;
  RoutePlanResult? _routePlan;

  int _activeOptionIndex = 0;
  String _planType = 'transit'; // "walk" | "transit"
  LatLng? _routingDestination;
  LatLng? _routingOrigin;
  String? _routingOriginLabel;
  String? _routingDestinationLabel;
  bool _useLiveCurrentOrigin = true;

  /// Local progress ticker. Since we no longer re-plan on a timer, this fires
  /// every second to recompute the user's progress along the committed route
  /// from the latest GPS fix — a purely on-device computation, no network.
  Timer? _progressTicker;
  bool _refreshInProgress = false;
  static const Duration _tickInterval = Duration(seconds: 1);

  RouteProgress? _routeProgress;

  /// Highest leg index the user has reached on the active option. Progress is
  /// forward-only: a route that overlaps itself (a line's outbound and inbound
  /// share roads) must never snap the user back to an earlier leg. Reset to 0
  /// when a new trip/plan/option begins.
  int _lastActiveSegment = 0;

  /// Live ETA (seconds) for the next incomplete bus leg, refreshed from
  /// `/transit/eta` every [_busEtaInterval]. Board ETA drives the real wait at
  /// the stop; alight ETA the "reach your stop" countdown. Null when there's no
  /// upcoming bus leg or the trip isn't being tracked.
  Timer? _busEtaTimer;
  static const Duration _busEtaInterval = Duration(seconds: 15);
  int? _liveEtaLegIndex;
  int? _liveBoardEtaSec;
  bool _liveBoardAtStop = false;
  int? _liveAlightEtaSec;
  bool _liveAlightAtStop = false;
  DateTime? _liveEtaFetchedAt;

  /// Whether the recommended bus has actually been seen dwelling AT the board
  /// stop. "Missed" then means it arrived and *left*, not merely that it's
  /// somewhere past the stop. Tracked per trip via [_boardEtaTripId].
  bool _busSeenAtBoardStop = false;
  String? _boardEtaTripId;

  // ── Live-bus co-location (fed from TransitProvider via [updateLiveTrips]) ──
  // Riding is confirmed by the *real* bus, not just GPS-on-road: the user left
  // the board stop with the bus and stays within [_coLocationMeters] of it —
  // so walking along the same road as the route can't read as "riding".
  List<Trip> _liveTrips = const [];

  /// Identifies the bus leg being tracked (routeId:board>alight), so the
  /// co-location latches reset when the user advances to a different bus leg.
  String? _coBusLegKey;

  /// User came within [_boardProximityMeters] of the active leg's board stop.
  bool _reachedBoardStop = false;

  /// Trip locked once boarding is confirmed, so tracking stays on the exact bus
  /// the user boarded even as other buses on the same route move around.
  String? _boardedTripId;

  /// Latest user↔bus distance (metres) for the tracked leg; null when there's
  /// no live bus. Drives the co-location decisions.
  double? _userBusMeters;

  /// When "still aboard past the alight stop" began — a missed alight must be
  /// *sustained* for [_missedAlightSustain] before it reroutes, so a brief
  /// overlap while getting off can't false-trigger it.
  DateTime? _pastAlightSince;

  static const double _boardProximityMeters = 10;
  static const double _coLocationMeters = 20;
  static const Duration _missedAlightSustain = Duration(seconds: 6);

  // ── Auto route simulation (walk 5 km/h → ride 25 km/h along the plan) ──────
  Timer? _simTimer;
  bool _routeSimActive = false;
  int _simSegIndex = 0;
  double _simDistIntoSeg = 0; // metres into the current segment's polyline
  DateTime _simLastTick = DateTime.now();

  /// Wall-clock acceleration so a long trip is watchable in a couple of minutes
  /// while keeping the walk:ride speed *ratio* realistic. Set to 1 for real time.
  static const double _simSpeedFactor = 8;
  static const Duration _simTickInterval = Duration(milliseconds: 400);

  bool get isRouteSimulating => _routeSimActive;

  /// Debounce for missed-bus re-plans so a stubbornly-behind bus can't trigger
  /// a re-plan storm. One-shot notice (the missed route's code) for the UI.
  DateTime? _lastMissedReplanAt;
  String? _missedBusNotice;

  /// Route code of a bus the user just missed — surfaced once by the UI (as a
  /// snackbar), then cleared via [clearMissedBusNotice].
  String? get missedBusNotice => _missedBusNotice;
  void clearMissedBusNotice() => _missedBusNotice = null;

  /// Set once when the user rides past their alight stop and a recovery re-plan
  /// is triggered. Surfaced once by the UI, then cleared.
  bool _passedStopReroute = false;
  bool get passedStopReroute => _passedStopReroute;
  void clearPassedStopReroute() => _passedStopReroute = false;

  /// Shadow re-plan: a silent background `/transit/plan` that keeps the user
  /// aware of a faster route WITHOUT disrupting their committed journey. It
  /// never blanks the card or changes the selection — it only surfaces a
  /// dismissible "faster route" suggestion. Paced by smart triggers (leg
  /// changes while not riding) plus a slow [_shadowInterval] fallback, and
  /// paused while riding (you're committed to the bus).
  Timer? _shadowTimer;
  // 60 s aligns with the backend's OPTION_HYSTERESIS_MS — options are stable
  // for that window, so re-planning faster just returns the same set.
  static const Duration _shadowInterval = Duration(seconds: 60);
  static const Duration _shadowDebounce = Duration(seconds: 45);
  static const int _fasterThresholdMin = 3;
  bool _shadowInProgress = false;
  DateTime? _lastShadowAt;

  /// Whether the route card is expanded enough to show the tabs. The 60 s tab
  /// refresh is skipped when it's collapsed/hidden — no point re-planning
  /// alternatives the user can't see. Set by the card.
  bool _routeSheetVisible = true;
  void setRouteSheetVisible(bool visible) => _routeSheetVisible = visible;
  RoutePlanResult? _shadowPlan;
  RouteOption? _fasterOption;
  int? _fasterSavingMinutes;
  String? _dismissedFasterId;

  /// A faster alternative than the committed route, or null. When set, the UI
  /// shows a dismissible banner offering to [switchToFasterRoute].
  RouteOption? get fasterSuggestion => _fasterOption;
  int? get fasterSavingMinutes => _fasterSavingMinutes;

  /// Live progress along the active route option, or null when not routing / no
  /// GPS. Recomputed each tick; drives the live ETA countdown and progress UI.
  RouteProgress? get routeProgress => _routeProgress;

  /// When non-null, the route info card is showing a saved favorite route, so
  /// the bookmark icon renders as already-saved. The route itself is re-planned
  /// through the normal `/transit/plan` flow (which polls for live ETAs).
  String? _activeFavoriteId;

  bool get showBusLines => _showBusLines;
  bool get isRoutingActive => _isRoutingActive;
  bool get isLoadingRoute => _isLoadingRoute;
  RoutePlanError? get routeError => _routeError;
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
      // A simulated origin overrides live GPS so the marker can't snap back.
      if (_simulatingLocation) return;
      _currentPosition = latLng;
      if (_activeCategoryKey != null) _recomputeNearbyCategory();
      notifyListeners();
      // Advance route progress promptly with each new fix (the 1 s ticker is a
      // fallback for when fixes are sparse).
      if (_isRoutingActive) _updateProgress();
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
    } catch (_) {
      // reverse geocoding is best-effort
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
    // A different journey — restart progress tracking from its first leg and
    // refresh the live bus ETA for the new option's bus leg.
    _lastActiveSegment = 0;
    _clearBusLegEta();
    // Manually picking a tab is the user taking control — drop any pending
    // faster-route suggestion.
    _clearFasterSuggestion();
    notifyListeners();
    _updateProgress();
    _refreshBusLegEta();
  }

  Future<void> setPlanType(String type) async {
    if (_planType == type) return;
    _planType = type;
    notifyListeners();
    if (_isRoutingActive && _routingDestination != null) {
      final origin = _activeOriginForQuery();
      if (origin == null) return;
      // New plan shape — restart progress tracking from the first leg.
      _lastActiveSegment = 0;
      _routeProgress = null;
      _lastShadowAt = null;
      _dismissedFasterId = null;
      _clearFasterSuggestion();
      _stopProgressTicker();
      await _fetchRoutePlan(origin: origin, destination: _routingDestination!);
      _startProgressTicker();
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
    _lastActiveSegment = 0;
    _routeProgress = null;
    _lastMissedReplanAt = null;
    _missedBusNotice = null;
    _passedStopReroute = false;
    _lastShadowAt = null;
    _dismissedFasterId = null;
    _clearFasterSuggestion();
    _resetCoLocation();
    _stopProgressTicker();
    await _fetchRoutePlan(origin: resolvedOrigin, destination: destination);
    _startProgressTicker();
  }

  void _startProgressTicker() {
    _progressTicker?.cancel();
    _busEtaTimer?.cancel();
    _shadowTimer?.cancel();
    if (_isRoutingActive) {
      _updateProgress();
      _progressTicker = Timer.periodic(_tickInterval, (_) => _updateProgress());
      _refreshBusLegEta();
      _busEtaTimer =
          Timer.periodic(_busEtaInterval, (_) => _refreshBusLegEta());
      _shadowTimer =
          Timer.periodic(_shadowInterval, (_) => _maybeShadowReplan());
    }
  }

  void _stopProgressTicker() {
    _progressTicker?.cancel();
    _progressTicker = null;
    _busEtaTimer?.cancel();
    _busEtaTimer = null;
    _shadowTimer?.cancel();
    _shadowTimer = null;
    _clearBusLegEta();
  }

  /// Refreshes the live ETA for the next incomplete bus leg — the bus's ETA to
  /// that leg's board stop (the real wait) and to its alight stop (the ride).
  /// Best-effort: on failure the last-known values are kept. No-op when the
  /// trip isn't being tracked (fixed-origin, non-simulated route).
  Future<void> _refreshBusLegEta() async {
    if (!_isRoutingActive) return;
    final option = activeOption;
    if (option == null || (!_useLiveCurrentOrigin && !_simulatingLocation)) {
      _clearBusLegEta();
      return;
    }
    int? idx;
    for (var i = _lastActiveSegment; i < option.segments.length; i++) {
      if (option.segments[i].isBus) {
        idx = i;
        break;
      }
    }
    final seg = idx == null ? null : option.segments[idx];
    // Prefer the live bus resolved by routeId over the plan's frozen tripId, so
    // a bus assigned after the plan was made still drives the ETA.
    final tripId =
        (seg == null ? null : _resolveLiveTrip(seg)?.id) ?? seg?.tripId;
    final alightStop = seg?.alightAt?.stopId;
    if (idx == null || tripId == null || alightStop == null) {
      _clearBusLegEta();
      return;
    }
    final boardStop = seg!.boardAt?.stopId;
    try {
      final results = await Future.wait([
        boardStop == null
            ? Future<StopEta?>.value(null)
            : _transitService.fetchStopEta(tripId: tripId, stopId: boardStop),
        _transitService.fetchStopEta(tripId: tripId, stopId: alightStop),
      ]);
      if (!_isRoutingActive) return;
      _liveEtaLegIndex = idx;
      _liveBoardEtaSec = results[0]?.etaSeconds;
      _liveBoardAtStop = results[0]?.atStop ?? false;
      // Reset the "seen at board stop" flag when the recommended trip changes,
      // then latch it once the bus is observed dwelling at the board stop.
      if (tripId != _boardEtaTripId) {
        _boardEtaTripId = tripId;
        _busSeenAtBoardStop = false;
      }
      if (_liveBoardAtStop) _busSeenAtBoardStop = true;
      _liveAlightEtaSec = results[1]?.etaSeconds;
      _liveAlightAtStop = results[1]?.atStop ?? false;
      _liveEtaFetchedAt = DateTime.now();
      _updateProgress();
      _maybeHandleMissedBus(seg);
      // Missed-alight now runs every tick inside _updateProgress (it needs the
      // sustained co-location window), so it is not called again here.
    } catch (_) {
      // best-effort — keep last-known ETA
    }
  }

  void _clearBusLegEta() {
    _liveEtaLegIndex = null;
    _liveBoardEtaSec = null;
    _liveBoardAtStop = false;
    _liveAlightEtaSec = null;
    _liveAlightAtStop = false;
    _liveEtaFetchedAt = null;
    _busSeenAtBoardStop = false;
    _boardEtaTripId = null;
  }

  /// Detects a missed bus: the recommended bus **was seen at the board stop and
  /// has now left it** while the user isn't aboard — i.e. it pulled away without
  /// them. (Requiring [_busSeenAtBoardStop] avoids flagging a bus that's merely
  /// "somewhere past" the stop without having stopped there.)
  ///
  /// Recovery keeps the SAME journey selected — it does NOT re-plan/replace the
  /// option. A silent refresh just rolls the journey's bus/ETA/times forward to
  /// the next trip (biased to the same route so the journey survives).
  Future<void> _maybeHandleMissedBus(RouteSegment busLeg) async {
    final riding = _routeProgress?.phase == RoutePhase.riding;
    final boardEta = _liveBoardEtaSec;
    final missed = !riding &&
        _busSeenAtBoardStop && // the bus actually reached the board stop…
        boardEta != null &&
        boardEta <= 0 &&
        !_liveBoardAtStop; // …and has now left it
    if (!missed) return;

    final now = DateTime.now();
    if (_lastMissedReplanAt != null &&
        now.difference(_lastMissedReplanAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastMissedReplanAt = now;
    _missedBusNotice = busLeg.route?.code ?? busLeg.route?.name;
    // Reset so the NEXT recommended bus can also be detected as missed.
    _busSeenAtBoardStop = false;
    notifyListeners();

    // Silent journey refresh — keeps the committed journey selected & live,
    // just updates its bus/ETA/times to the next trip. Never blanks the card
    // or switches the selected option.
    final routeId = busLeg.route?.id;
    await _shadowReplan(preferRouteIds: routeId != null ? [routeId] : const []);
    _clearBusLegEta();
    _refreshBusLegEta();
  }

  /// Detects riding *past* the alight stop: while on the bus, the alight-stop
  /// ETA has hit 0 and the bus isn't dwelling there — i.e. the user overshot.
  /// Getting off correctly instead advances the phase off `riding`, so this
  /// only fires when they genuinely stayed aboard. Recovers by re-planning from
  /// the current (past) position, so the planner routes them back.
  void _maybeHandleMissedStop(RouteSegment busLeg) {
    if (_routeProgress?.phase != RoutePhase.riding) {
      _pastAlightSince = null;
      return;
    }

    final alightIdx = busLeg.alightAt?.stopIndex;
    final trip = _resolveLiveTrip(busLeg);

    bool overshot;
    if (trip != null && alightIdx != null && _userBusMeters != null) {
      // Live path: the bus has left the alight stop AND the user is still
      // co-located with it — i.e. they stayed aboard. Require this to be
      // sustained ([_missedAlightSustain]) so a brief overlap while alighting
      // (or a bus briefly stuck alongside a parallel walk) can't trigger it.
      final stillAboard = trip.currentStopIndex > alightIdx &&
          _userBusMeters! <= _coLocationMeters;
      if (stillAboard) {
        _pastAlightSince ??= DateTime.now();
        overshot = DateTime.now().difference(_pastAlightSince!) >=
            _missedAlightSustain;
      } else {
        _pastAlightSince = null;
        overshot = false;
      }
    } else {
      // No live bus — fall back to the ETA-based signal (single-shot).
      final alightEta = _liveAlightEtaSec;
      overshot = alightEta != null && alightEta <= 0 && !_liveAlightAtStop;
    }
    if (!overshot) return;

    final now = DateTime.now();
    if (_lastMissedReplanAt != null &&
        now.difference(_lastMissedReplanAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastMissedReplanAt = now;
    _pastAlightSince = null;
    _passedStopReroute = true;
    notifyListeners();
    // No route bias — recovery may need a different line to come back.
    _replanForMissedBus(null);
  }

  Future<void> _replanForMissedBus(String? routeId) async {
    if (_refreshInProgress) return;
    final origin = _activeOriginForQuery();
    final destination = _routingDestination;
    if (origin == null || destination == null) return;
    // A recovery re-plan is effectively a fresh journey from here — restart
    // leg tracking so progress projects onto the new route from its start.
    _lastActiveSegment = 0;
    _routeProgress = null;
    _resetCoLocation();
    _refreshInProgress = true;
    try {
      // Keep the committed journey shape where a later trip exists (sticky +
      // route bias); fall back to a fresh best when it doesn't.
      await _fetchRoutePlan(
        origin: origin,
        destination: destination,
        preserveSelection: true,
        preferRouteIds: routeId != null ? [routeId] : const [],
      );
    } finally {
      _refreshInProgress = false;
    }
    // Refresh live ETA against the new trip immediately.
    _clearBusLegEta();
    _refreshBusLegEta();
  }

  /// Runs a shadow re-plan when it's worth it: the trip is tracked, the card is
  /// on screen, the trip isn't finished, and we haven't checked too recently.
  /// Refreshing the *alternative* tabs is safe in every state (they're passive
  /// — the user follows the selected option), so this runs while riding too;
  /// only the faster-route *suggestion* is held back mid-ride (see below).
  void _maybeShadowReplan() {
    if (!_isRoutingActive) return;
    if (!_useLiveCurrentOrigin && !_simulatingLocation) return;
    if (!_routeSheetVisible) return;
    if (_routeProgress?.phase == RoutePhase.arrived) return;
    final now = DateTime.now();
    if (_lastShadowAt != null && now.difference(_lastShadowAt!) < _shadowDebounce) {
      return;
    }
    _lastShadowAt = now;
    _shadowReplan();
  }

  /// Silently re-plans in the background, then:
  ///  1. refreshes the *unselected* tabs with the freshest alternatives while
  ///     keeping the committed journey pinned and live (so its tracking is
  ///     never disturbed and it can never vanish from the tabs), and
  ///  2. when the user can act on it (not mid-ride), surfaces a materially
  ///     faster alternative as the dismissible banner.
  Future<void> _shadowReplan({List<String> preferRouteIds = const []}) async {
    if (_shadowInProgress) return;
    final origin = _activeOriginForQuery();
    final dest = _routingDestination;
    if (origin == null || dest == null || activeOption == null) return;

    _shadowInProgress = true;
    try {
      final plan = await _transitService.fetchRoutePlan(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destLat: dest.latitude,
        destLng: dest.longitude,
        type: _planType,
        preferRouteIds: preferRouteIds,
      );
      // Re-read after the await — the user may have switched tabs meanwhile.
      final committed = activeOption;
      if (!_isRoutingActive ||
          committed == null ||
          !plan.found ||
          plan.options.isEmpty) {
        return;
      }

      final committedId = committed.id;
      // Fresh copy of the committed journey when the planner still returns it;
      // otherwise keep the current object so the pinned tab never disappears.
      final committedFresh = committedId == null
          ? null
          : plan.options.where((o) => o.id == committedId).firstOrNull;
      final pinned = committedFresh ?? committed;

      // The other tabs: freshest alternatives, excluding the committed journey.
      final others = plan.options
          .where((o) => committedId == null || o.id != committedId)
          .take(4)
          .toList();

      final merged = <RouteOption>[pinned, ...others]
        ..sort((a, b) =>
            a.totalEstimatedMinutes.compareTo(b.totalEstimatedMinutes));

      // Swap in the refreshed tabs. Using the same pinned object (or its fresh
      // same-id copy) means `activeOption` is unchanged in shape, so progress
      // tracking continues uninterrupted — we do NOT reset `_lastActiveSegment`.
      _routePlan = RoutePlanResult(
        found: true,
        type: plan.type,
        options: merged,
      );
      _activeOptionIndex = merged.indexOf(pinned).clamp(0, merged.length - 1);

      // Faster-route banner — only when the user can act (not mid-ride) and
      // the fastest is a materially quicker, different, non-dismissed journey.
      final fastest = merged.first;
      final saving = pinned.totalEstimatedMinutes - fastest.totalEstimatedMinutes;
      final riding = _routeProgress?.phase == RoutePhase.riding;
      if (!riding &&
          fastest.id != pinned.id &&
          saving >= _fasterThresholdMin &&
          fastest.id != _dismissedFasterId) {
        _shadowPlan = plan;
        _fasterOption = fastest;
        _fasterSavingMinutes = saving;
      } else {
        _clearFasterSuggestion();
      }

      notifyListeners();
      _updateProgress();
    } catch (_) {
      // shadow re-plan is best-effort — never surfaces an error
    } finally {
      _shadowInProgress = false;
    }
  }

  /// Adopts the suggested faster route (user tapped "Switch" on the banner).
  /// This is an explicit choice, so it swaps in the fresh plan and restarts
  /// tracking on the faster option.
  void switchToFasterRoute() {
    final plan = _shadowPlan;
    final opt = _fasterOption;
    if (plan == null || opt == null) return;
    _routePlan = plan;
    final idx = plan.options.indexWhere((o) => o.id == opt.id);
    _activeOptionIndex = idx >= 0 ? idx : 0;
    _lastActiveSegment = 0;
    _routeProgress = null;
    _clearBusLegEta();
    _clearFasterSuggestion();
    notifyListeners();
    _updateProgress();
    _refreshBusLegEta();
  }

  /// Dismisses the suggestion; the same option won't be re-suggested this trip.
  void dismissFasterSuggestion() {
    _dismissedFasterId = _fasterOption?.id;
    _clearFasterSuggestion();
    notifyListeners();
  }

  void _clearFasterSuggestion() {
    _shadowPlan = null;
    _fasterOption = null;
    _fasterSavingMinutes = null;
  }

  /// Pushed by the map UI whenever [TransitProvider] emits new live positions,
  /// so riding/co-location tracks the real bus in near-real-time (MQTT ~1 s)
  /// rather than only on the GPS/ETA cadence.
  void updateLiveTrips(List<Trip> trips) {
    _liveTrips = trips;
    if (_isRoutingActive) _updateProgress();
  }

  /// The live bus currently serving [leg], matched by **routeId** against the
  /// live feed — not the plan's frozen `tripId` — so a bus assigned after the
  /// plan was made is picked up automatically. A trip locked by boarding wins;
  /// otherwise the one furthest along toward boarding that hasn't yet passed
  /// the alight stop.
  Trip? _resolveLiveTrip(RouteSegment leg) {
    final routeId = leg.route?.id;
    if (routeId == null || _liveTrips.isEmpty) return null;
    final alightIdx = leg.alightAt?.stopIndex;
    final locked = _boardedTripId;
    if (locked != null) {
      for (final t in _liveTrips) {
        if (t.id == locked && t.routeId == routeId) return t;
      }
    }
    Trip? best;
    for (final t in _liveTrips) {
      if (t.routeId != routeId) continue;
      if (alightIdx != null && t.currentStopIndex > alightIdx) continue;
      if (best == null || t.currentStopIndex > best.currentStopIndex) best = t;
    }
    return best;
  }

  String _busLegKey(RouteSegment leg) =>
      '${leg.route?.id}:${leg.boardAt?.stopIndex}>${leg.alightAt?.stopIndex}';

  /// The bus leg the user is currently on, or null when the active leg is a
  /// walk (or nothing is being tracked).
  RouteSegment? _trackedBusLeg() {
    final option = activeOption;
    final prog = _routeProgress;
    if (option == null || prog == null) return null;
    final i = prog.activeSegmentIndex;
    if (i < 0 || i >= option.segments.length) return null;
    final seg = option.segments[i];
    return seg.isBus ? seg : null;
  }

  void _resetCoLocation() {
    _coBusLegKey = null;
    _reachedBoardStop = false;
    _boardedTripId = null;
    _pastAlightSince = null;
    _userBusMeters = null;
  }

  /// Phase for a bus leg. Prefers live co-location with the real bus; falls back
  /// to the GPS-on-road heuristic when no live bus is available for this leg.
  ///
  /// Riding is confirmed only when the user reached the board stop
  /// (≤ [_boardProximityMeters]), the matched bus has left the board stop, and
  /// the user stays within [_coLocationMeters] of it — so walking down the same
  /// road as the route can't read as "riding". Once confirmed, the exact trip
  /// is locked ([_boardedTripId]).
  RoutePhase _busLegPhase(RouteSegment leg, LatLng pos, double fraction) {
    // Reset the co-location latches when we move onto a different bus leg.
    final key = _busLegKey(leg);
    if (key != _coBusLegKey) {
      _coBusLegKey = key;
      _reachedBoardStop = false;
      _boardedTripId = null;
      _pastAlightSince = null;
    }

    final boardIdx = leg.boardAt?.stopIndex;
    final boardCoord = leg.boardAt?.coordinates;
    if (boardCoord != null &&
        _distance(pos, boardCoord) <= _boardProximityMeters) {
      _reachedBoardStop = true;
    }

    final trip = _resolveLiveTrip(leg);
    final busPos = trip?.currentLocation;
    _userBusMeters = busPos == null ? null : _distance(pos, busPos);

    if (trip != null && busPos != null && boardIdx != null) {
      final coLocated = _userBusMeters! <= _coLocationMeters;
      final boarded = _boardedTripId == trip.id;
      final busLeftBoard = trip.currentStopIndex > boardIdx;
      if (coLocated &&
          (busLeftBoard || boarded) &&
          (_reachedBoardStop || boarded)) {
        _boardedTripId = trip.id; // lock onto the exact bus the user boarded
        return RoutePhase.riding;
      }
      return RoutePhase.waiting;
    }

    // No live bus for this leg — fall back to the road-projection heuristic.
    return fraction < 0.02 ? RoutePhase.waiting : RoutePhase.riding;
  }

  /// Recomputes [_routeProgress] from the latest GPS fix against the active
  /// option and notifies listeners only when the displayed values change.
  /// Purely local — no `/plan` call.
  void _updateProgress() {
    if (!_isRoutingActive) return;
    final prev = _routeProgress;
    final prevSeg = prev?.activeSegmentIndex;
    final next = _computeProgress();
    // Adopt immediately so the co-location check below sees the fresh phase.
    _routeProgress = next;

    // Missed-alight is co-location + *sustained*, so it must run every tick
    // (not only on the 15 s ETA poll) to track the sustain window.
    final busLeg = _trackedBusLeg();
    if (busLeg != null) _maybeHandleMissedStop(busLeg);

    // Notify only when the displayed values actually change.
    if (next == null && prev == null) return;
    if (next != null && next.sameAs(prev)) return;
    notifyListeners();
    // Advancing to a new leg (e.g. boarding) — refresh the live bus ETA now
    // instead of waiting for the 15 s tick, and re-check for a faster route
    // (a smart trigger on top of the slow shadow timer).
    if (next != null && next.activeSegmentIndex != prevSeg) {
      _refreshBusLegEta();
      _maybeShadowReplan();
    }
  }

  /// Projects the user's position onto the active option's legs to find which
  /// leg they're on, how far along it, and the distance/time still to go. The
  /// remaining legs contribute their full plan estimate; the active leg is
  /// scaled by how far along it the user already is, so the ETA ticks down.
  RouteProgress? _computeProgress() {
    // Progress only means something when the traveler's position corresponds to
    // this route — i.e. the trip is anchored to the user's live location, or
    // we're simulating movement. A route planned between two fixed places must
    // not be "tracked" against the phone's unrelated GPS (which would otherwise
    // project onto some leg and, at worst, read as already "Arrived").
    if (!_useLiveCurrentOrigin && !_simulatingLocation) return null;

    final pos = _currentPosition;
    final option = activeOption;
    if (pos == null || option == null || option.segments.isEmpty) return null;

    // Distance to each leg's geometry, and how far along that leg the user is.
    final dists = <int, double>{};
    final fracs = <int, double>{};
    for (var i = 0; i < option.segments.length; i++) {
      final proj = projectOntoPath(pos, _segmentPolyline(option.segments[i]));
      if (proj == null) continue;
      dists[i] = proj.distanceMeters;
      fracs[i] = proj.fraction;
    }
    if (dists.isEmpty) return null;

    // Forward-only: only consider the current leg and later ones, so an
    // overlapping return leg can't drag progress backward.
    final candidates = dists.keys.where((i) => i >= _lastActiveSegment).toList()
      ..sort();
    final searchSet = candidates.isNotEmpty
        ? candidates
        : (dists.keys.toList()..sort());

    // Among candidates, take the closest — but when two legs are within a small
    // tolerance (a line's outbound & inbound run along the same road), prefer
    // the EARLIEST, so we stay on the current leg until the user clearly moves
    // onto a later one instead of skipping ahead.
    const overlapToleranceMeters = 30.0;
    var minDist = double.infinity;
    for (final i in searchSet) {
      if (dists[i]! < minDist) minDist = dists[i]!;
    }
    var bestSeg = searchSet.first;
    for (final i in searchSet) {
      if (dists[i]! <= minDist + overlapToleranceMeters) {
        bestSeg = i;
        break;
      }
    }
    _lastActiveSegment = bestSeg;
    final bestFraction = fracs[bestSeg] ?? 0;

    // Walk a "clock" forward through the remaining legs. Most legs just add
    // their remaining minutes, but the next bus leg with live ETA folds in the
    // REAL wait: you board at max(when-you-reach-the-stop, when-the-bus-does),
    // so the wait and ride reflect the live bus instead of the plan's estimate.
    // Decay the (up to 15 s old) ETAs by the time since they were fetched so
    // the countdown ticks smoothly between refreshes instead of drifting.
    final liveIdx = _liveEtaLegIndex;
    final elapsedSec = _liveEtaFetchedAt == null
        ? 0.0
        : DateTime.now().difference(_liveEtaFetchedAt!).inMilliseconds / 1000.0;
    final liveBoardMin = _liveBoardEtaSec != null
        ? ((_liveBoardEtaSec! - elapsedSec).clamp(0.0, double.infinity)) / 60.0
        : null;
    final liveAlightMin = _liveAlightEtaSec != null
        ? ((_liveAlightEtaSec! - elapsedSec).clamp(0.0, double.infinity)) / 60.0
        : null;

    double metersLeft = 0;
    double clock = 0; // minutes from now
    int? busLegIndex;
    int? busBoardSeconds;
    int? busAlightSeconds;
    for (var i = bestSeg; i < option.segments.length; i++) {
      final seg = option.segments[i];
      final remaining = i == bestSeg ? (1 - bestFraction) : 1.0;
      metersLeft += _segmentMeters(seg) * remaining;

      if (seg.isBus && i == liveIdx && liveAlightMin != null) {
        // Board ETA (bus → board stop); fall back to alight − static ride.
        final board = liveBoardMin ?? (liveAlightMin - (seg.rideMinutes ?? 0));
        final ride = (liveAlightMin - board).clamp(0.0, double.infinity);
        busLegIndex = i;
        // Surface the bus's arrival at the board stop ("arrives in N") — more
        // actionable than a wait. The header countdown still folds in the real
        // wait via the max() below.
        busBoardSeconds = (board.clamp(0.0, double.infinity) * 60).round();
        busAlightSeconds = (liveAlightMin * 60).round();
        clock = (clock > board ? clock : board) + ride; // max(clock, board)+ride
      } else {
        clock += _segmentMinutes(seg) * remaining;
      }
    }

    final active = option.segments[bestSeg];
    final isLast = bestSeg == option.segments.length - 1;
    final RoutePhase phase;
    if (isLast && (bestFraction >= 0.98 || metersLeft < 25)) {
      phase = RoutePhase.arrived;
    } else if (active.isBus) {
      phase = _busLegPhase(active, pos, bestFraction);
    } else {
      phase = RoutePhase.walking;
    }

    return RouteProgress(
      activeSegmentIndex: bestSeg,
      phase: phase,
      fractionAlongSegment: bestFraction,
      metersRemaining: metersLeft.round(),
      minutesRemaining: clock.round(),
      busLegIndex: busLegIndex,
      busBoardSeconds: busBoardSeconds,
      busAlightSeconds: busAlightSeconds,
    );
  }

  /// Road geometry for a leg, falling back to a straight line between its
  /// endpoints (or its stop chain) when the backend supplied no `path`.
  List<LatLng> _segmentPolyline(RouteSegment seg) {
    if (seg.path.isNotEmpty) return seg.path;
    if (seg.isWalk) {
      final from = seg.from?.coordinates, to = seg.to?.coordinates;
      if (from != null && to != null) return [from, to];
    } else {
      final board = seg.boardAt?.coordinates;
      final alight = seg.alightAt?.coordinates;
      if (board != null && alight != null) {
        return [
          board,
          ...seg.intermediateStops.map((s) => s.coordinates),
          alight,
        ];
      }
    }
    return const [];
  }

  double _segmentMeters(RouteSegment seg) =>
      (seg.distanceMeters ?? 0).toDouble();

  double _segmentMinutes(RouteSegment seg) {
    if (seg.isWalk) return (seg.estimatedMinutes ?? 0).toDouble();
    return (seg.totalLegMinutes ??
            ((seg.waitMinutes ?? 0) + (seg.rideMinutes ?? 0)))
        .toDouble();
  }

  Future<void> _fetchRoutePlan({
    required LatLng origin,
    required LatLng destination,
    // Sticky selection: keep the user's committed journey across a re-plan of
    // the SAME trip (retry / off-route). A changed origin or destination is a
    // different trip, so it plans fresh and selects the new best option.
    bool preserveSelection = false,
    // Bias ranking toward these routes (missed-bus re-plan keeps the same line).
    List<String> preferRouteIds = const [],
  }) async {
    final prevSignature =
        preserveSelection ? _optionSignature(activeOption) : null;

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
        preferRouteIds: preferRouteIds,
        // Transit planning can be slow server-side; give the user-initiated
        // fetch a generous budget before giving up.
        timeout: const Duration(seconds: 25),
      );
      _routePlan = plan;
      _activeOptionIndex =
          preserveSelection ? _restoreSelection(plan, prevSignature) : 0;
    } catch (e) {
      _routeError = _classifyRoutePlanError(e);
    } finally {
      _isLoadingRoute = false;
      notifyListeners();
    }
  }

  /// Signature identifying a journey's *shape* for sticky selection. Prefers
  /// the backend's stable option `id`; falls back to the bus legs'
  /// route+board/alight stop ids for legacy responses without an id. Returns
  /// null for a pure-walk option (nothing stable to match on).
  String? _optionSignature(RouteOption? option) {
    if (option == null) return null;
    if (option.id != null) return option.id;
    final busLegs = option.segments.where((s) => s.isBus).toList();
    if (busLegs.isEmpty) return null;
    return busLegs
        .map((s) => '${s.route?.id}:${s.boardAt?.stopId}>${s.alightAt?.stopId}')
        .join('|');
  }

  /// Index of the option in [plan] matching [signature], or 0 when there is no
  /// match — the first plan of a trip, or the committed journey genuinely no
  /// longer exists in the new plan.
  int _restoreSelection(RoutePlanResult plan, String? signature) {
    if (signature == null || !plan.found) return 0;
    for (var i = 0; i < plan.options.length; i++) {
      if (_optionSignature(plan.options[i]) == signature) return i;
    }
    return 0;
  }

  /// Maps a raw plan-fetch exception to a user-facing category. The UI renders
  /// a friendly localized message per category — the raw error is never shown.
  RoutePlanError _classifyRoutePlanError(Object e) {
    if (e is TimeoutException) return RoutePlanError.timeout;
    // package:http throws ClientException for connection failures on every
    // platform (including web), so no dart:io SocketException needed.
    if (e is http.ClientException) return RoutePlanError.offline;
    return RoutePlanError.generic;
  }

  /// Re-runs the route plan for the current origin/destination — wired to the
  /// "Try again" button shown when a plan fetch fails, and the entry point for
  /// future event-driven re-plans (off-route / missed-bus). Guarded so a slow
  /// backend can't produce overlapping requests, and preserves the user's
  /// committed journey via sticky selection.
  Future<void> retryRoutePlan() async {
    if (_refreshInProgress) return;
    final origin = _activeOriginForQuery();
    final destination = _routingDestination;
    if (origin == null || destination == null) return;
    _refreshInProgress = true;
    try {
      // Same trip (origin/destination unchanged) — keep the committed journey.
      await _fetchRoutePlan(
        origin: origin,
        destination: destination,
        preserveSelection: true,
      );
    } finally {
      _refreshInProgress = false;
    }
  }

  // ── Location simulation (route-planner testing) ───────────────────────────

  /// Overrides the user's current location with [position] for testing the
  /// route tracker. Freezes real GPS (so it can't snap the marker back) and,
  /// while a route is active, recomputes progress from the simulated point —
  /// so dropping successive points along the route shows the ETA countdown and
  /// per-leg progress update as if the user were moving, without re-planning
  /// (matching the plan-once model real trips now use).
  void setSimulatedPosition(LatLng position) {
    _simulatingLocation = true;
    _currentPosition = position;
    if (_activeCategoryKey != null) _recomputeNearbyCategory();
    notifyListeners();
    if (_isRoutingActive) _updateProgress();
  }

  /// Exits simulation mode; the next real GPS fix resumes control of the marker.
  void stopSimulatingLocation() {
    _stopRouteSim();
    if (!_simulatingLocation) return;
    _simulatingLocation = false;
    notifyListeners();
  }

  /// One-tap auto-drive: animates the simulated "current location" along the
  /// active plan — walk legs at ~5 km/h, bus legs at ~25 km/h (accelerated by
  /// [_simSpeedFactor]) — from the origin to the destination, so the whole
  /// walking → waiting → riding → arrived flow can be watched without tapping.
  void startRouteSimulation() {
    final option = activeOption;
    if (!_isRoutingActive || option == null || option.segments.isEmpty) return;
    _resetCoLocation();
    _lastActiveSegment = 0;
    _routeProgress = null;
    _simSegIndex = 0;
    _simDistIntoSeg = 0;
    _simLastTick = DateTime.now();
    _simulatingLocation = true;
    _routeSimActive = true;
    final startPoly = _segmentPolyline(option.segments.first);
    if (startPoly.isNotEmpty) _currentPosition = startPoly.first;
    notifyListeners();
    _updateProgress();
    _simTimer?.cancel();
    _simTimer = Timer.periodic(_simTickInterval, (_) => _simStep());
  }

  /// Stops the auto-drive and exits simulation mode.
  void stopRouteSimulation() {
    _stopRouteSim();
    _simulatingLocation = false;
    notifyListeners();
  }

  void _stopRouteSim() {
    _simTimer?.cancel();
    _simTimer = null;
    _routeSimActive = false;
  }

  void _simStep() {
    final option = activeOption;
    if (!_routeSimActive || !_isRoutingActive || option == null) {
      _stopRouteSim();
      return;
    }
    final segs = option.segments;
    final now = DateTime.now();
    final dt = now.difference(_simLastTick).inMilliseconds / 1000.0;
    _simLastTick = now;

    var advance =
        _simSegIndex < segs.length
        ? _speedMps(segs[_simSegIndex]) * _simSpeedFactor * dt
        : 0.0;

    // Walk the cursor forward, carrying overflow into later segments.
    while (advance > 0 && _simSegIndex < segs.length) {
      final poly = _segmentPolyline(segs[_simSegIndex]);
      final len = _polylineLength(poly);
      if (poly.length < 2 || len <= 0) {
        _simSegIndex++;
        _simDistIntoSeg = 0;
        continue;
      }
      final room = len - _simDistIntoSeg;
      if (advance < room) {
        _simDistIntoSeg += advance;
        advance = 0;
      } else {
        advance -= room;
        _simSegIndex++;
        _simDistIntoSeg = 0;
      }
    }

    if (_simSegIndex >= segs.length) {
      final lastPoly = _segmentPolyline(segs.last);
      if (lastPoly.isNotEmpty) _currentPosition = lastPoly.last;
      _stopRouteSim();
      notifyListeners();
      _updateProgress();
      return;
    }

    _currentPosition =
        _pointAlong(_segmentPolyline(segs[_simSegIndex]), _simDistIntoSeg);
    notifyListeners();
    _updateProgress();
  }

  double _speedMps(RouteSegment seg) {
    const walkMps = 5000.0 / 3600.0; // 5 km/h
    const busMps = 25000.0 / 3600.0; // 25 km/h
    return seg.isBus ? busMps : walkMps;
  }

  double _polylineLength(List<LatLng> pts) {
    var d = 0.0;
    for (var i = 1; i < pts.length; i++) {
      d += _distance(pts[i - 1], pts[i]);
    }
    return d;
  }

  /// The point [dist] metres along [pts], clamped to its ends.
  LatLng _pointAlong(List<LatLng> pts, double dist) {
    if (pts.isEmpty) return _currentPosition ?? const LatLng(0, 0);
    if (pts.length == 1) return pts.first;
    var acc = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final segLen = _distance(pts[i - 1], pts[i]);
      if (acc + segLen >= dist) {
        final t = segLen <= 0 ? 0.0 : (dist - acc) / segLen;
        return LatLng(
          pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * t,
          pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * t,
        );
      }
      acc += segLen;
    }
    return pts.last;
  }

  void clearRouting() {
    _stopProgressTicker();
    _stopRouteSim();
    _routeProgress = null;
    _lastActiveSegment = 0;
    _lastMissedReplanAt = null;
    _missedBusNotice = null;
    _passedStopReroute = false;
    _lastShadowAt = null;
    _dismissedFasterId = null;
    _clearFasterSuggestion();
    _resetCoLocation();
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
    } catch (_) {
      // recent searches are best-effort
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
    } catch (_) {
      // recent searches are best-effort
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
    _stopProgressTicker();
    _positionSub?.cancel();
    super.dispose();
  }
}

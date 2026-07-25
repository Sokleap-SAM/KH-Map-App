import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
import 'package:kh_map_app/models/route_stop.dart';
import 'package:kh_map_app/models/trip.dart';
import 'package:kh_map_app/providers/transit_provider.dart';
import 'package:kh_map_app/widgets/map/bus_markers_layer.dart';
import 'package:kh_map_app/widgets/map/map_pick_banner.dart';
import 'package:kh_map_app/widgets/map/route_info_card.dart';
import 'package:kh_map_app/widgets/map/route_search_overlay.dart';
import 'package:kh_map_app/widgets/map/routing_overlay_layer.dart';
import 'package:kh_map_app/widgets/map/transit_route_layer.dart';
import 'package:kh_map_app/widgets/map_screen/pin.dart';
import 'package:kh_map_app/models/trip_eta.dart';
import 'package:kh_map_app/services/mqtt_service.dart';
import 'package:kh_map_app/utils/eta.dart';
import 'package:kh_map_app/widgets/map_screen/place_detail_sheet.dart';
import 'package:kh_map_app/widgets/map_screen/search_bar.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/favorite_route.dart';
import '../models/route_plan.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../utils/constants/colors.dart';
import '../services/favorite_routes_service.dart';
import '../services/favorites_service.dart';
import '../widgets/map/locate_me_button.dart';
import '../widgets/map/place_markers_layer.dart';
import '../widgets/map/user_location_marker_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FavoritesService _favoritesService = FavoritesService();
  final FavoriteRoutesService _favoriteRoutesService = FavoriteRoutesService();

  // Centralized Khmer normalization to handle variations in spacing and symbols
  String _normalizeKhmer(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '') // Zero-width spaces
        .replaceAll(RegExp(r'[|.\-\s]'), '') // Symbols and standard spaces
        .replaceAll(RegExp(r'\s+'), ''); // Any remaining whitespace
  }

  double _currentZoom = 13.0;
  /// While true, the next map tap sets a simulated "current location" for
  /// testing the route planner instead of dropping a pin.
  bool _simulatePickMode = false;
  final Set<String> _selectedRouteIds = {};
  bool _seededFilterFromRoutes = false;
  final Set<String> _favoritePlaceIds = {};

  // Cached provider refs + memoized MQTT route set for the live-tracking wiring:
  // TransitProvider positions feed MapProvider's co-location riding detection,
  // and the active trip's routes stay subscribed even if unchecked in the filter.
  MapProvider? _mapProvider;
  TransitProvider? _transitProvider;
  Set<String> _lastMqttRoutes = {};

  /// Pushes the current filter to TransitProvider, which opens/closes the
  /// matching MQTT topic subscriptions. Safe to call repeatedly; the provider
  /// only acts on the diff.
  void _syncMqttSubscriptions() {
    final routes = Set<String>.from(_selectedRouteIds);
    // During a trip, always track the committed journey's bus-leg routes — even
    // if the user unchecked them in the filter — so live tracking never breaks.
    final map = _mapProvider;
    if (map != null && map.isRoutingActive) {
      final opt = map.activeOption;
      if (opt != null) {
        for (final seg in opt.segments) {
          final id = seg.route?.id;
          if (seg.isBus && id != null) routes.add(id);
        }
      }
    }
    if (routes.length == _lastMqttRoutes.length &&
        routes.containsAll(_lastMqttRoutes)) {
      return;
    }
    _lastMqttRoutes = routes;
    (_transitProvider ?? context.read<TransitProvider>())
        .setSubscribedRoutes(routes);
  }

  // Feed live bus positions into MapProvider on every MQTT tick (co-location
  // riding detection).
  void _onTransitTrips() {
    _mapProvider?.updateLiveTrips(_transitProvider?.trips ?? const []);
  }

  // Re-sync subscriptions when routing starts/stops or the active option
  // changes, so the trip's routes get added/removed. Memoized, so the frequent
  // progress-tick notifications are cheap no-ops.
  void _onRoutingChanged() => _syncMqttSubscriptions();

  @override
  void initState() {
    super.initState();
    _mapProvider = context.read<MapProvider>();
    _transitProvider = context.read<TransitProvider>();
    _mapProvider!.init();
    _transitProvider!.init();
    _loadFavorites();
    AuthService.tokenNotifier.addListener(_onAuthChanged);
    _transitProvider!.addListener(_onTransitTrips);
    _mapProvider!.addListener(_onRoutingChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() => _favoritePlaceIds.clear());
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await _favoritesService.load();
      if (!mounted) return;
      setState(() {
        _favoritePlaceIds
          ..clear()
          ..addAll(favorites.map((f) => f.placeId));
      });
    } catch (_) {
      // favorites are best-effort
    }
  }

  Future<void> _toggleFavorite(Place place, bool isFav) async {
    setState(() {
      if (isFav) {
        _favoritePlaceIds.add(place.id);
      } else {
        _favoritePlaceIds.remove(place.id);
      }
    });
    try {
      if (isFav) {
        await _favoritesService.add(place);
      } else {
        await _favoritesService.remove(place.id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isFav) {
          _favoritePlaceIds.remove(place.id);
        } else {
          _favoritePlaceIds.add(place.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save favorite. Try again.')),
      );
    }
  }

  @override
  void dispose() {
    AuthService.tokenNotifier.removeListener(_onAuthChanged);
    _transitProvider?.removeListener(_onTransitTrips);
    _mapProvider?.removeListener(_onRoutingChanged);
    _mapController.dispose();
    super.dispose();
  }

  /// Persists [option] (the active route plan option) as a favorite route.
  /// Returns the new favorite's id on success (so the bookmark icon can flip to
  /// its saved state and later remove it), or null on failure.
  Future<String?> _saveFavoriteRoute(RouteOption option) async {
    final provider = context.read<MapProvider>();
    final t = context.read<SettingsProvider>().t;
    final originPos = provider.routingOrigin;
    final destPos = provider.routingDestination;

    if (originPos == null || destPos == null) {
      _snack(t.couldNotSaveThisRoute);
      return null;
    }

    // A favorite stores a FIXED origin coordinate, so a live "current location"
    // label would be misleading once the user moves. Resolve the saved point to
    // a stable address (falling back to coordinates) in that case.
    final originLabel = provider.routingOriginLabel;
    final originName =
        (provider.useLiveCurrentOrigin ||
            originLabel == null ||
            originLabel.trim().isEmpty)
        ? await provider.reverseGeocodeLabel(originPos)
        : originLabel;

    final origin = FavoriteRouteEndpoint(
      name: originName,
      coordinates: originPos,
    );
    final destination = FavoriteRouteEndpoint(
      name: provider.routingDestinationLabel ?? t.destinationLabel,
      coordinates: destPos,
    );

    try {
      final saved = await _favoriteRoutesService.add(
        origin: origin,
        destination: destination,
        label: '${origin.name} → ${destination.name}',
      );
      _snack(t.routeSavedToBookmarks);
      return saved.id;
    } catch (e) {
      _snack(t.couldNotSaveRoute);
      return null;
    }
  }

  /// Removes the favorite route saved during this routing view.
  Future<bool> _removeFavoriteRoute(String favoriteId) async {
    final t = context.read<SettingsProvider>().t;
    try {
      await _favoriteRoutesService.remove(favoriteId);
      _snack(t.routeRemovedFromBookmarks);
      return true;
    } catch (e) {
      _snack(t.couldNotRemoveRoute);
      return false;
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(message),
      ),
    );
  }

  // ── Map interactions ──────────────────────────────────────────────────────

  void _focusOnPlace(Place place) {
    final target = LatLng(place.latitude, place.longitude);
    context.read<MapProvider>().setFollowUser(false);
    _mapController.move(target, 17);
    context.read<MapProvider>().addToRecentSearches(place.id);
    _showPlaceDetail(context, place);
  }

  /// Filters the map to every place in the tapped category and frames them.
  void _onCategorySelected(MapCategory category) {
    final provider = context.read<MapProvider>();
    final user = provider.currentPosition;

    final results = provider.toggleCategoryFilter(
      key: category.key,
      keywords: category.keywords,
    );

    // Tapping the active category again clears the filter — recenter on user.
    if (!provider.hasCategoryFilter) {
      if (user != null) _mapController.move(user, 15);
      return;
    }

    provider.setFollowUser(false);

    if (results.isEmpty) {
      final t = context.read<SettingsProvider>().t;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              t.categoryNotFoundNearby(t.mapCategoryLabel(category.key)),
            ),
          ),
        );
      if (user != null) _mapController.move(user, 15);
      return;
    }

    // Frame every match (and the user) so the whole category is on screen.
    final points = <LatLng>[
      ?user,
      for (final p in results) LatLng(p.latitude, p.longitude),
    ];
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(60, 220, 60, 160),
        maxZoom: 16.5,
      ),
    );
  }

  void _centerOnUser() {
    final provider = context.read<MapProvider>();
    if (provider.currentPosition != null) {
      _mapController.move(
        provider.currentPosition!,
        _mapController.camera.zoom,
      );
      provider.setFollowUser(true);
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    final mapProvider = context.read<MapProvider>();
    // Location-simulation mode: set a fake "current location" for testing the
    // route planner, then let the provider re-plan from it.
    if (_simulatePickMode) {
      setState(() => _simulatePickMode = false);
      mapProvider.setSimulatedPosition(latLng);
      _snack(context.read<SettingsProvider>().t.simulatedLocationSet);
      return;
    }
    // Map-pick mode: provider reverse-geocodes and fires the pending callback.
    if (mapProvider.isMapPickMode) {
      mapProvider.handleMapPickTap(latLng);
      return;
    }
    // Don't drop a pin while a route is active or the route search overlay
    // is open — a new pin would re-trigger openRouteSearch and overwrite the
    // origin/destination the user is currently editing.
    if (mapProvider.isRoutingActive || mapProvider.showRouteSearch) return;
    mapProvider.dropPin(latLng);
    _showPinSheet();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    final Animation<double> animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void _onBusStopTap(LatLng latLng) {
    context.read<MapProvider>().setFollowUser(false);
    _animatedMapMove(latLng, 17.0);
  }

  // ── Bottom sheets ─────────────────────────────────────────────────────────

  void _showPinSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ChangeNotifierProvider.value(
          value: context.read<MapProvider>(),
          child: Consumer<MapProvider>(
            builder: (ctx, provider, _) {
              if (provider.droppedPin == null) return const SizedBox.shrink();
              return PinInfoSheet(
                latitude: provider.droppedPin!.latitude,
                longitude: provider.droppedPin!.longitude,
                placeName: provider.droppedPinPlace,
                road: provider.droppedPinRoad,
                isLoading: provider.isLoadingPinInfo,
                onDirections: () {
                  final pin = provider.droppedPin!;
                  final label = provider.droppedPinPlace ?? 'Dropped Pin';

                  provider.openRouteSearch(
                    RouteSearchSelection(label: label, location: pin),
                  );
                },
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        final provider = context.read<MapProvider>();
        if (!provider.isRoutingActive) provider.removePin();
      }
    });
  }

  void _showPlaceDetail(BuildContext context, Place place) {
    final String cat = (place.category?.name ?? '').toLowerCase();
    // Scan both names so the check works in either language.
    final String name =
        '${place.nameInKhmer} ${place.nameInLatin}'.toLowerCase();

    // Extremely robust check: covers categories or names containing 'bus' or 'stop'
    if (cat.contains('bus') ||
        cat.contains('stop') ||
        cat.contains('transit') ||
        name.contains('bus stop') ||
        name.contains('ចំណត')) {
      _showBusStopPanel(place);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceDetailSheet(
        place: place,
        initialFavorite: _favoritePlaceIds.contains(place.id),
        onFavoriteChanged: (isFav) => _toggleFavorite(place, isFav),
        onDirections: () {
          context.read<MapProvider>().openRouteSearch(
            RouteSearchSelection(
              label: place.localizedName(
                context.read<SettingsProvider>().languageCode,
              ),
              location: LatLng(place.latitude, place.longitude),
            ),
          );
        },
      ),
    );
  }

  Future<void> _viewBusByTripId(String tripId) async {
    final transit = context.read<TransitProvider>();
    final local = transit.trips.where((t) => t.id == tripId).firstOrNull;
    if (local != null) {
      _showBusDetails(local);
      return;
    }
    // Not in the active-trips list — diagnose, then fall back to a by-id fetch
    // (the trip may be broadcasting over MQTT without being in that feed).
    if (kDebugMode) {
      debugPrint(
        'View bus: tripId="$tripId" not in active trips '
        '[${transit.trips.map((t) => t.id).join(", ")}] — fetching by id',
      );
    }
    final fetched = await transit.loadTripById(tripId);
    if (!mounted) return;
    if (fetched != null) {
      _showBusDetails(fetched);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.read<SettingsProvider>().t.couldNotViewBusInfo),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showBusStopPanel(Place stop) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            final transit = context.watch<TransitProvider>();
            final settings = context.watch<SettingsProvider>();
            // Named `tx` — `t` is used for Trip in the builders below.
            final tx = settings.t;
            final stopName = _normalizeKhmer(stop.name);

            final stopTrips = transit.trips.where((t) {
              final hasStop = t.allStops.any((s) {
                final normS = _normalizeKhmer(s);
                return normS.contains(stopName) ||
                    stopName.contains(
                      normS,
                    ); // Use normalized names for comparison
              });
              final bool isActive = !t.isCompleted && !t.isCancelled;
              return hasStop &&
                  isActive; // Only return true if both conditions are met
            }).toList();
            Trip? closestBus;
            int minStopsAway = 999;
            for (var trip in stopTrips) {
              final stopIdx = trip.allStops.indexWhere((s) {
                final normS = _normalizeKhmer(s);
                return normS.contains(stopName) || stopName.contains(normS);
              });

              if (stopIdx != -1 && trip.nextStopIndex <= stopIdx) {
                final away =
                    stopIdx - trip.nextStopIndex; // Calculate stops away
                if (away < minStopsAway) {
                  minStopsAway = away;
                  closestBus = trip;
                }
              }
            }
            final displayTrip =
                closestBus ?? (stopTrips.isNotEmpty ? stopTrips.first : null);

            // Filter out the closest bus to get "Other" trips
            final otherTrips = stopTrips
                .where((t) => t.id != displayTrip?.id)
                .toList();

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── FIXED HEADER ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1976D2),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 15),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Text(
                          tx.busStopHeader,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        Text(
                          // Display localized; matching above stays on the
                          // Khmer name because trip.allStops holds Khmer.
                          stop.localizedName(settings.languageCode),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (closestBus != null) ...[
                          const SizedBox(height: 15),
                          _buildClosestBusCard(closestBus, minStopsAway),
                        ],
                      ],
                    ),
                  ),
                  // ── SCROLLABLE CONTENT ────────────────────────────────
                  Expanded(
                    child: closestBus != null
                        ? TripStopsList(
                            controller: scrollController,
                            trip: closestBus,
                            currentStopName: stop.name,
                            header: [
                              const SizedBox(height: 20),
                              Text(
                                tx.routeItineraryHeader,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 15),
                            ],
                            trailing: [
                              if (otherTrips.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Text(
                                  tx.otherBusLinesHeader,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...otherTrips.map((t) => _buildStopTripItem(t)),
                              ],
                            ],
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (otherTrips.isNotEmpty) ...[
                                Text(
                                  tx.otherBusLinesHeader,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...otherTrips.map((t) => _buildStopTripItem(t)),
                              ] else
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Text(
                                      "No active buses at this stop",
                                      style: TextStyle(
                                        color: Colors.white24,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClosestBusCard(Trip trip, int stopsAway) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 30, height: 30, child: BusPulseIndicator()),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stopsAway == 0 ? "Arriving now" : "$stopsAway stops away",
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  "Route ${trip.routeNumber} - ${trip.direction}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.white),
            tooltip: "Track Live Location",
            onPressed: () {
              Navigator.pop(context); // Close stop panel
              if (trip.currentLocation != null) {
                _mapController.move(trip.currentLocation!, 16);
              }
              _showBusDetails(trip); // Open the bus live location sheet
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStopTripItem(Trip trip) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            trip.routeNumber ?? '?',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: Text(
        trip.routeName ?? 'Bus Route',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        "To: ${trip.direction}",
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        color: Colors.white12,
        size: 14,
      ),
      onTap: () {
        Navigator.pop(context);
        _showBusDetails(trip);
      },
    );
  }

  void _showBusDetails(Trip trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final tx = context.watch<SettingsProvider>().t;
        return Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1976D2),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.routeHeaderShort,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              trip.routeNumber ?? 'N/A',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(51),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            children: [
                              Text(
                                tx.plateNumber,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                trip.busNumber ?? '??z',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_bus_filled,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            trip.routeName ?? 'Unknown Route',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _InfoBox(
                            label: tx.statusLabel,
                            content: const Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: Colors.green,
                                  size: 10,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  "In service",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _LiveEtaBox(tripId: trip.id)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(13),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBD8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.bus_alert,
                              color: Color(0xFFE8B67D),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx.nextStopHeader,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                ),
                                Text(
                                  trip.nextStopName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        _buildActionButton(
                          Icons.list,
                          "All stops",
                          onTap: () {
                            Navigator.pop(context);
                            _showAllStopsPanel(trip);
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildActionButton(
                          Icons.map_outlined,
                          "Directions",
                          onTap: () {
                            Navigator.pop(context);
                            _showDirectionsPanel(trip);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRouteSelector() {
    // Snapshot once — the modal owns its own setState for redraws.
    final transit = context.read<TransitProvider>();
    final lineRoutes = transit.lineRoutes;
    final routeColors = transit.routeColors;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        final tx = context.watch<SettingsProvider>().t;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tx.selectRoutesHeader,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  CheckboxListTile(
                    title: Text(
                      tx.showAll,
                      style: const TextStyle(color: Colors.white),
                    ),
                    value:
                        lineRoutes.isNotEmpty &&
                        _selectedRouteIds.length == lineRoutes.length,
                    activeColor: const Color(0xFFE8B67D),
                    onChanged: (bool? val) {
                      setState(() {
                        if (val == true) {
                          _selectedRouteIds
                            ..clear()
                            ..addAll(lineRoutes.map((r) => r.id));
                        } else {
                          _selectedRouteIds.clear();
                        }
                      });
                      _syncMqttSubscriptions();
                      setModalState(() {});
                    },
                  ),
                  const Divider(color: Colors.white10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: lineRoutes.length,
                      itemBuilder: (context, index) {
                        final route = lineRoutes[index];
                        final isSelected = _selectedRouteIds.contains(route.id);
                        final color = routeColors[route.id] ?? Colors.blue;

                        return CheckboxListTile(
                          activeColor: color,
                          secondary: Icon(Icons.directions_bus, color: color),
                          title: Text(
                            tx.routeCodeLabel(route.code ?? '??'),
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            route.name ?? '',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (isSelected) {
                                _selectedRouteIds.remove(route.id);
                              } else {
                                _selectedRouteIds.add(route.id);
                              }
                            });
                            _syncMqttSubscriptions();
                            setModalState(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAllStopsPanel(Trip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollController.hasClients) {
                scrollController.animateTo(
                  (trip.nextStopIndex * 60.0).clamp(
                    0.0,
                    scrollController.position.maxScrollExtent,
                  ),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                );
              }
            });
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      context.watch<SettingsProvider>().t.allStopsHeader,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TripStopsList(
                      trip: trip,
                      controller: scrollController,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showDirectionsPanel(Trip trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final tx = context.watch<SettingsProvider>().t;
        return Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tx.directionsHeader,
                style: const TextStyle(
                  color: Color(0xFFE8B67D),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.radio_button_checked,
                    color: Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 15),
                  Text(
                    tx.startColon,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  Expanded(
                    child: Text(
                      trip.allStops.first,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(left: 9),
                height: 30,
                width: 2,
                color: Colors.white10,
              ),
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 15),
                  Text(
                    tx.destinationColon,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  Expanded(
                    child: Text(
                      trip.direction,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Center(
                child: Text(
                  tx.navigationComingSoon,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white24, fontSize: 12),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Origin marker for the route-search preview — the same `Icons.trip_origin`
  /// + `Colors.greenAccent` shown next to the origin field in the overlay,
  /// wrapped in a white disc so the hollow ring stays readable on the map.
  Marker _originPreviewMarker(LatLng point) {
    return Marker(
      point: point,
      width: 24,
      height: 24,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.trip_origin, color: Colors.green, size: 24),
      ),
    );
  }

  /// Destination marker for the route-search preview — an orange drop-pin
  /// matching the `Icons.location_on` shown next to the destination field.
  /// Anchored at the bottom so the tip touches [point].
  Marker _destinationPreviewMarker(LatLng point) {
    return Marker(
      point: point,
      width: 28,
      height: 36,
      alignment: Alignment.topCenter,
      child: const Icon(
        Icons.location_on,
        color: Color(0xFFF97316),
        size: 36,
        shadows: [
          Shadow(color: Colors.black45, blurRadius: 5, offset: Offset(0, 2)),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label, {
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          side: const BorderSide(color: Colors.white12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MapProvider>();
    final transitProvider = context.watch<TransitProvider>();
    final t = context.watch<SettingsProvider>().t;

    final List<Place> displayPlaces;
    if (provider.hasCategoryFilter) {
      // A category is active — show every match for it at any zoom, so the
      // results the banner counts are actually visible on the map.
      displayPlaces = provider.nearbyCategoryPlaces;
    } else {
      displayPlaces = provider.places.where((place) {
        final bool isRecent = provider.recentSearchIds.contains(place.id);

        // 1. If it's a recent search, show it from Zoom 10.0 (Far away)
        if (isRecent) return _currentZoom >= 10.0;

        // 2. If it's a normal place, show it from Zoom 16.5 (Close up)
        return _currentZoom >= 16.5;
      }).toList();
    }

    // Seed the filter with every route once they load.
    if (transitProvider.lineRoutes.isNotEmpty && !_seededFilterFromRoutes) {
      final ids = transitProvider.lineRoutes.map((r) => r.id).toList();
      if (ids.isNotEmpty) {
        _selectedRouteIds.addAll(ids);
        _seededFilterFromRoutes = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncMqttSubscriptions();
      });
    }

    final displayRoutes = transitProvider.lineRoutes
        .where((r) => _selectedRouteIds.contains(r.id))
        .toList();
    final displayTrips = transitProvider.trips
        .where((t) => _selectedRouteIds.contains(t.routeId))
        .toList();

    if (provider.locationError) {
      return const Center(
        child: Text('Location permission is required to use the map.'),
      );
    }

    if (provider.currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.followUser) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(
          provider.currentPosition!,
          _mapController.camera.zoom,
        );
      });
    }

    // One-shot camera move (e.g. framing a favorite route's origin opened from
    // the bookmark tab). Consume it so it only happens once.
    final camTarget = provider.cameraMoveTarget;
    if (camTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(camTarget, 14);
        provider.consumeCameraMoveTarget();
      });
    }

    // One-shot notice when a missed bus triggers a re-plan for the next one.
    final missedBus = provider.missedBusNotice;
    if (missedBus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(t.missedBusReplanning(missedBus));
        provider.clearMissedBusNotice();
      });
    }

    // One-shot notice when the user rode past their stop and we re-route.
    if (provider.passedStopReroute) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snack(t.passedStopRerouting);
        provider.clearPassedStopReroute();
      });
    }

    return Stack(
      children: [
        // ── Map ───────────────────────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: provider.currentPosition!,
            initialZoom: _currentZoom,
            minZoom: 5,
            maxZoom: 18,
            onPositionChanged: (camera, hasGesture) {
              if (camera.zoom != _currentZoom) {
                setState(() => _currentZoom = camera.zoom);
              }
            },
            onTap: _onMapTap,
            onMapEvent: (event) {
              if (event is MapEventMoveStart &&
                  event.source != MapEventSource.mapController) {
                context.read<MapProvider>().setFollowUser(false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.kh_map_app',
            ),
            // States A/B: full bus route polylines (zoom-gated).
            // if (provider.showBusLines && _currentZoom >= 12.0)
            TransitRouteLayer(
              routes: displayRoutes,
              routeStops: transitProvider.routeStops,
              onStopTap: _onBusStopTap,
              routeColors: transitProvider.routeColors,
              currentZoom: _currentZoom,
            ),
            // State C: routing overlay.
            if (provider.isRoutingActive && provider.activeOption != null)
              RoutingOverlayLayer(option: provider.activeOption!),
            // Live preview pins while the route-search overlay is open.
            // Hidden once routing starts — RoutingOverlayLayer paints its own
            // numbered markers from then on.
            if (provider.showRouteSearch && !provider.isRoutingActive)
              MarkerLayer(
                markers: [
                  if (provider.routeSearchOriginPin != null)
                    _originPreviewMarker(provider.routeSearchOriginPin!),
                  if (provider.routeSearchDestinationPin != null)
                    _destinationPreviewMarker(
                      provider.routeSearchDestinationPin!,
                    ),
                ],
              ),
            if (_currentZoom >= 12.0)
              BusMarkersLayer(
                trips: displayTrips,
                routeColors: transitProvider.routeColors,
                onBusTap: _showBusDetails,
              ),

            PlaceMarkersLayer(
              places: displayPlaces,
              recentSearchIds: provider.recentSearchIds,
              currentZoom: _currentZoom,
              onTap: _showPlaceDetail,
            ),
            UserLocationMarkerLayer(position: provider.currentPosition!),
          ],
        ),

        // ── Top bar: search bar OR route search overlay ──────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child:
              provider.showRouteSearch &&
                  provider.routeSearchDestination != null
              ? RouteSearchOverlay(
                  currentLocation: provider.currentPosition!,
                  initialDestination: provider.routeSearchDestination!,
                  initialOrigin: provider.routeSearchOrigin,
                  onClose: () {
                    // Close the overlay and clear any active routing so the
                    // `RouteInfoCard` is removed when the user taps back.
                    if (_simulatePickMode) {
                      setState(() => _simulatePickMode = false);
                    }
                    provider.closeRouteSearch();
                    provider.clearRouting();
                    provider.removePin();
                  },
                  onSubmit: ({required origin, required destination}) =>
                      provider.submitRouteSearch(
                        origin: origin,
                        destination: destination,
                      ),
                  onRequestMapPick: (onPicked) =>
                      provider.startMapPick(onPicked),
                  onSelectionChanged:
                      ({required origin, required destination}) =>
                          provider.updateRouteSearchPins(
                            origin: origin,
                            destination: destination,
                          ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      color: Colors.white,
                      height: MediaQuery.of(context).padding.top,
                    ),
                    MapSearchBar(
                      onPlaceSelected: _focusOnPlace,
                      activeCategory: provider.activeCategoryKey,
                      onCategorySelected: _onCategorySelected,
                    ),
                    if (provider.hasCategoryFilter)
                      _NearbyResultsBanner(
                        count: provider.nearbyCategoryPlaces.length,
                        onClear: () {
                          provider.clearCategoryFilter();
                          final user = provider.currentPosition;
                          if (user != null) _mapController.move(user, 15);
                        },
                      ),
                  ],
                ),
        ),

        // ── Route filter ────────────────────────────────────────────────
        Positioned(
          bottom: 100,
          right: 16,
          child: FloatingActionButton(
            heroTag: 'route_filter',
            mini: true,
            backgroundColor: const Color(0xFF1A2B4C),
            onPressed: _showRouteSelector,
            child: const Icon(
              Icons.alt_route,
              color: Color(0xFFE8B67D),
              size: 20,
            ),
          ),
        ),

        // ── Location-simulation button (route-planner testing) ──────────
        // While routing, drop a fake "current location" on the map to watch
        // the planner re-route and ETAs refresh as if the user were moving.
        if (provider.isRoutingActive)
          Positioned(
            right: 16,
            bottom: 176,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (provider.isSimulatingLocation)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FloatingActionButton(
                      heroTag: 'sim_stop',
                      mini: true,
                      backgroundColor: Colors.white,
                      tooltip: t.stopSimulating,
                      onPressed: () {
                        provider.stopSimulatingLocation();
                        _snack(t.liveLocationRestored);
                      },
                      child: const Icon(
                        Icons.gps_fixed,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                  ),
                // One-tap auto-drive: walk 5 km/h → ride 25 km/h along the plan.
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FloatingActionButton(
                    heroTag: 'sim_auto',
                    mini: true,
                    backgroundColor: provider.isRouteSimulating
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF1A2B4C),
                    tooltip: t.autoSimulate,
                    onPressed: () {
                      if (provider.isRouteSimulating) {
                        provider.stopRouteSimulation();
                        _snack(t.liveLocationRestored);
                      } else {
                        provider.startRouteSimulation();
                        _snack(t.autoSimulateStarted);
                      }
                    },
                    child: Icon(
                      provider.isRouteSimulating
                          ? Icons.stop
                          : Icons.play_arrow,
                      color: provider.isRouteSimulating
                          ? Colors.white
                          : const Color(0xFFE8B67D),
                      size: 20,
                    ),
                  ),
                ),
                FloatingActionButton(
                  heroTag: 'sim_pick',
                  mini: true,
                  backgroundColor: _simulatePickMode
                      ? const Color(0xFFF97316)
                      : const Color(0xFF1A2B4C),
                  tooltip: t.simulateLocation,
                  onPressed: () {
                    setState(() => _simulatePickMode = !_simulatePickMode);
                    if (_simulatePickMode) _snack(t.simulateLocationHint);
                  },
                  child: Icon(
                    _simulatePickMode
                        ? Icons.touch_app
                        : Icons.edit_location_alt,
                    color: _simulatePickMode
                        ? Colors.white
                        : const Color(0xFFE8B67D),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

        // ── Locate-me button ─────────────────────────────────────────────
        LocateMeButton(
          isLoading: provider.placesLoading,
          followUser: provider.followUser,
          onPressed: _centerOnUser,
        ),

        // ── Map-pick hint banner (reads provider internally) ─────────────
        const MapPickBanner(),

        // ── Route info card (State C) ────────────────────────────────────
        if (provider.isRoutingActive)
          RouteInfoCard(
            onClear: () {
              if (_simulatePickMode) {
                setState(() => _simulatePickMode = false);
              }
              provider.clearRouting();
              provider.removePin();
            },
            onShowBusDetail: _viewBusByTripId,
            onSaveFavorite: _saveFavoriteRoute,
            onRemoveFavorite: _removeFavoriteRoute,
          ),
      ],
    );
  }
}

class TripStopsList extends StatefulWidget {
  final Trip trip;
  final ScrollController? controller;
  final bool shrinkWrap;
  final String? currentStopName;
  final List<Widget>? header;
  final List<Widget>? trailing;

  const TripStopsList({
    super.key,
    required this.trip,
    this.controller,
    this.shrinkWrap = false,
    this.trailing,
    this.header,
    this.currentStopName,
  });

  @override
  State<TripStopsList> createState() => _TripStopsListState();
}

class _TripStopsListState extends State<TripStopsList> {
  late ScrollController _internalScrollController;
  bool _isScrolledToTop = true;
  int? _currentStopIndex; // Index of the currentStopName if found

  // Flag to track if the initial scroll to current stop has happened
  bool _initialScrollDone = false;

  @override
  void initState() {
    super.initState();
    _internalScrollController = widget.controller ?? ScrollController();
    _internalScrollController.addListener(_scrollListener);

    _findCurrentStopIndex();

    // Auto-scroll to the current stop or next stop after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_internalScrollController.hasClients && !_initialScrollDone) {
        int targetIndex = _currentStopIndex ?? widget.trip.nextStopIndex;
        if (targetIndex != -1) {
          _scrollToIndex(targetIndex);
          _initialScrollDone = true;
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant TripStopsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStopName != widget.currentStopName ||
        oldWidget.trip != widget.trip) {
      _findCurrentStopIndex();
    }
  }

  String _normalizeKhmer(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[|.\-\s]'), '')
        .replaceAll(RegExp(r'\s+'), '');
  }

  void _findCurrentStopIndex() {
    if (widget.currentStopName != null) {
      final target = _normalizeKhmer(widget.currentStopName!);
      _currentStopIndex = widget.trip.allStops.indexWhere((s) {
        final normS = _normalizeKhmer(s);
        return normS.contains(target) || target.contains(normS);
      });
    } else {
      _currentStopIndex = null;
    }
  }

  void _scrollListener() {
    if (!_internalScrollController.hasClients) return;

    final bool newIsScrolledToTop =
        _internalScrollController.position.pixels == 0;
    if (_isScrolledToTop != newIsScrolledToTop) {
      setState(() {
        _isScrolledToTop = newIsScrolledToTop;
      });
    }
  }

  void _scrollToIndex(int index) {
    const itemHeight = 66.0; // Estimated height per stop item
    final viewportHeight = _internalScrollController.position.viewportDimension;

    // Account for headers if any
    double headerHeight = 0;
    if (widget.header != null) headerHeight = 50.0;

    // Calculate target offset to center the item in the middle of the viewport
    final targetOffset =
        headerHeight +
        (index * itemHeight) -
        (viewportHeight / 2) +
        (itemHeight / 2);

    _internalScrollController.animateTo(
      targetOffset.clamp(
        0.0,
        _internalScrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScrollButtonPress() {
    if (_isScrolledToTop &&
        _currentStopIndex != null &&
        _currentStopIndex != -1) {
      // If at top and there's a current stop, scroll to it
      _scrollToIndex(_currentStopIndex!);
    } else {
      // Otherwise, scroll to top
      _internalScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _internalScrollController.removeListener(_scrollListener);
    if (widget.controller == null) {
      // Only dispose if we created it
      _internalScrollController.dispose();
    }
    super.dispose();
  }

  double _calculateSegmentProgress(Trip trip, List<String> allStops) {
    if (trip.currentLocation == null || trip.nextStopIndex <= 0) return 0.0;

    // We need the coordinates of the previous stop and the next stop
    // Since we only have names in 'allStops', we should look at the
    // 'routeStops' from the provider to get LatLngs.
    final provider = context.read<TransitProvider>();
    final stops = provider.routeStops[trip.routeId] ?? [];

    if (stops.length <= trip.nextStopIndex) return 0.0;

    final LatLng prevStopLoc = stops[trip.nextStopIndex - 1].location;
    final LatLng nextStopLoc = stops[trip.nextStopIndex].location;
    final LatLng busLoc = trip.currentLocation!;

    final Distance distance = const Distance();

    double totalSegmentDist = distance.as(
      LengthUnit.Meter,
      prevStopLoc,
      nextStopLoc,
    );
    double busDistFromStart = distance.as(
      LengthUnit.Meter,
      prevStopLoc,
      busLoc,
    );

    if (totalSegmentDist == 0) return 0.0;
    return (busDistFromStart / totalSegmentDist).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the scroll button should be shown
    bool showScrollButton = false;
    if (widget.currentStopName != null &&
        _currentStopIndex != null &&
        _currentStopIndex != -1) {
      // Always show button if there's a specific stop to track
      showScrollButton = true;
    } else if (!_isScrolledToTop) {
      // Show scroll to top if not at top and no specific stop to track
      showScrollButton = true;
    }

    // Determine the icon for the scroll button
    IconData buttonIcon;
    if (_isScrolledToTop &&
        widget.currentStopName != null &&
        _currentStopIndex != null &&
        _currentStopIndex != -1) {
      buttonIcon = Icons.arrow_downward; // Scroll to current stop
    } else {
      buttonIcon = Icons.arrow_upward; // Scroll to top
    }

    return Stack(
      children: [
        Scrollbar(
          controller: _internalScrollController,
          thumbVisibility: true,
          thickness: 4,
          radius: const Radius.circular(10),
          child: ListView.builder(
            controller: _internalScrollController,
            shrinkWrap: widget.shrinkWrap,
            physics: widget.shrinkWrap
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            itemCount:
                (widget.header?.length ?? 0) +
                widget.trip.allStops.length +
                (widget.trailing?.length ?? 0),
            itemBuilder: (context, index) {
              // Handle Header Widgets
              if (widget.header != null && index < widget.header!.length) {
                return widget.header![index];
              }

              final int stopIndex = index - (widget.header?.length ?? 0);

              // Handle Trailing Widgets
              if (stopIndex >= widget.trip.allStops.length) {
                return widget.trailing![stopIndex -
                    widget.trip.allStops.length];
              }

              // Handle Itinerary Items
              final stopName = widget.trip.allStops[stopIndex];
              bool isTarget = stopIndex == widget.trip.nextStopIndex;
              bool isPassed = stopIndex < widget.trip.nextStopIndex;
              bool isLast = stopIndex == widget.trip.allStops.length - 1;
              bool isLinePassed = stopIndex < (widget.trip.nextStopIndex - 1);
              bool isLineLoading = stopIndex == (widget.trip.nextStopIndex - 1);

              bool isCurrentSelectedStop =
                  widget.currentStopName != null &&
                  (stopName.toLowerCase().contains(
                        widget.currentStopName!.toLowerCase(),
                      ) ||
                      widget.currentStopName!.toLowerCase().contains(
                        stopName.toLowerCase(),
                      ));

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. THE TIMELINE LANE
                    SizedBox(
                      width: 40,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 30,
                            child: Center(
                              child: isTarget
                                  ? const BusPulseIndicator()
                                  : Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isPassed
                                            ? const Color(0xFF1976D2)
                                            : Colors.white10,
                                        border: isCurrentSelectedStop
                                            ? Border.all(
                                                color: Colors.greenAccent,
                                                width: 2,
                                              )
                                            : null,
                                      ),
                                    ),
                            ),
                          ),
                          if (!isLast)
                            Expanded(
                              child: Center(
                                child: DrivingBusConnector(
                                  isPassed: isLinePassed,
                                  isLoading: isLineLoading,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 2. THE STATION NAME
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 40),
                        child: Text(
                          stopName,
                          style: TextStyle(
                            color: isCurrentSelectedStop
                                ? Colors.greenAccent
                                : (isTarget
                                      ? Colors.white
                                      : (isPassed
                                            ? Colors.white70
                                            : Colors.white24)),
                            fontSize: 16,
                            height: 1.4,
                            fontWeight: (isTarget || isCurrentSelectedStop)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
              );
            },
          ),
        ),
        if (showScrollButton)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'trip_stops_scroll',
              mini: true,
              backgroundColor: const Color(0xFF1976D2),
              onPressed: _handleScrollButtonPress,
              child: Icon(buttonIcon, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// Thin banner under the search bar summarising the active nearby-category
/// search, with a button to clear it.
class _NearbyResultsBanner extends StatelessWidget {
  const _NearbyResultsBanner({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Container(
      width: double.infinity,
      color: AppColors.primaryColor,
      padding: const EdgeInsets.only(left: 16, right: 8, bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.near_me, color: AppColors.secondaryColor, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == 0 ? t.notFoundShort : t.foundPlaces(count),
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 16, color: Colors.white70),
            label: Text(
              t.clearFilter,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class BusPulseIndicator extends StatefulWidget {
  const BusPulseIndicator({super.key});

  @override
  State<BusPulseIndicator> createState() => _BusPulseIndicatorState();
}

class _BusPulseIndicatorState extends State<BusPulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(); // Makes it pulse forever
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // The growing "Radar" ring
            Container(
              width: 12 + (24 * _controller.value),
              height: 12 + (24 * _controller.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(
                  0xFF1976D2,
                ).withValues(alpha: 1 - _controller.value),
              ),
            ),
            // The solid center dot
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1976D2),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class FlowingLineConnector extends StatefulWidget {
  final bool isPassed;
  final bool isLoading;

  const FlowingLineConnector({
    super.key,
    required this.isPassed,
    required this.isLoading,
  });

  @override
  State<FlowingLineConnector> createState() => _FlowingLineConnectorState();
}

class _FlowingLineConnectorState extends State<FlowingLineConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Increase duration to 1.5 seconds for a smoother flow
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    if (widget.isLoading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(FlowingLineConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the bus moves, start or stop the animation
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. If the segment is already passed, show a solid blue line
    if (widget.isPassed) {
      return Container(width: 2.5, color: const Color(0xFF1976D2));
    }

    // 2. If the segment is currently loading (the bus is on it)
    if (widget.isLoading) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Container(
            width: 2.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                // This math slides the gradient from -3 to +3
                // creating a "window" of light that flows down
                begin: Alignment(0, -1 + (_controller.value * 6)),
                end: Alignment(0, -2 + (_controller.value * 6)),
                colors: const [
                  Color(0xFF1976D2), // Dark Blue
                  Color.fromARGB(255, 46, 59, 77), // Bright Light
                  Color(0xFF1976D2), // Dark Blue
                ],
              ),
            ),
          );
        },
      );
    }

    // 3. If it's a future segment, show a dim grey line
    return Container(width: 2, color: Colors.white10);
  }
}

/// ETA panel inside the bus detail card. Fetches a one-shot snapshot from
/// `/transit/trips/:id/eta` on open, then re-derives the displayed number
/// every time [TransitProvider] notifies (i.e. on every MQTT position tick).
class _LiveEtaBox extends StatefulWidget {
  const _LiveEtaBox({required this.tripId});

  final String tripId;

  @override
  State<_LiveEtaBox> createState() => _LiveEtaBoxState();
}

class _LiveEtaBoxState extends State<_LiveEtaBox> {
  TripEtaSnapshot? _snapshot;
  bool _snapshotLoaded = false;
  VoidCallback? _unsubscribeDetail;

  @override
  void initState() {
    super.initState();
    _subscribeDetail();
  }

  @override
  void dispose() {
    _unsubscribeDetail?.call();
    super.dispose();
  }

  Future<void> _subscribeDetail() async {
    try {
      final unsub = await MqttService.instance.subscribeToTripDetail(
        widget.tripId,
        _onDetail,
      );
      if (!mounted) {
        unsub();
        return;
      }
      _unsubscribeDetail = unsub;
    } catch (e) {
      if (!mounted) return;
      setState(() => _snapshotLoaded = true);
    }
  }

  void _onDetail(Map<String, dynamic> json) {
    if (!mounted) return;
    try {
      final snap = TripEtaSnapshot.fromJson(json);
      setState(() {
        _snapshot = snap;
        _snapshotLoaded = true;
      });
    } catch (_) {
      // ignore malformed detail payloads
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransitProvider>();
    final trip = provider.trips.where((t) => t.id == widget.tripId).firstOrNull;
    final stops = trip == null
        ? const <RouteStop>[]
        : (provider.routeStops[trip.routeId] ?? const <RouteStop>[]);

    final (label, value) = _resolveLabel(trip, stops);
    return _box(label, value);
  }

  (String, String) _resolveLabel(Trip? trip, List<RouteStop> stops) {
    // No MQTT-derived position yet → fall back to the one-shot snapshot.
    final hasLive =
        trip?.currentLocation != null &&
        trip?.speed != null &&
        stops.isNotEmpty;

    if (!hasLive) {
      if (!_snapshotLoaded) return ('ETA', '—');
      final snap = _snapshot;
      if (snap == null) return ('ETA', '—');
      if (snap.notDepartingUntilMs != null &&
          snap.notDepartingUntilMs! > DateTime.now().millisecondsSinceEpoch) {
        return ('Departs in', '~${snap.etaMinutes ?? 0} min');
      }
      if (snap.isDwelling) return ('Status', 'At stop');
      if (snap.etaMinutes != null) {
        return ('Arrives in', '~${snap.etaMinutes} min');
      }
      return ('ETA', '—');
    }

    final seconds = etaToNextStopSeconds(
      currentPos: trip!.currentLocation!,
      speedKmh: trip.speed,
      currentStopIndex: trip.currentStopIndex,
      stops: stops,
      notDepartingUntilMs: trip.notDepartingUntilMs,
    );

    if (seconds == null) return ('Status', 'At stop');

    final minutes = (seconds / 60).round();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final parked =
        trip.notDepartingUntilMs != null && trip.notDepartingUntilMs! > nowMs;
    return (parked ? 'Departs in' : 'Arrives in', '~$minutes min');
  }

  Widget _box(String label, String value) {
    return _InfoBox(
      label: label,
      content: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Compact two-line info card used in the bus detail sheet (status, ETA, …).
class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.content});

  final String label;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 5),
          content,
        ],
      ),
    );
  }
}

class DrivingBusConnector extends StatefulWidget {
  final bool isPassed;
  final bool isLoading;

  const DrivingBusConnector({
    super.key,
    required this.isPassed,
    required this.isLoading,
  });

  @override
  State<DrivingBusConnector> createState() => _DrivingBusConnectorState();
}

class _DrivingBusConnectorState extends State<DrivingBusConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Speed of the driving bus
    );

    _positionAnimation = Tween<double>(
      begin: -1.0,
      end: 1.0,
    ).animate(_controller);

    if (widget.isLoading) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(DrivingBusConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isLoading) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. If passed, show solid blue line
    if (widget.isPassed) {
      return Container(width: 2.5, color: const Color(0xFF1976D2));
    }

    // 2. If currently driving on this segment
    if (widget.isLoading) {
      return AnimatedBuilder(
        animation: _positionAnimation,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The Track (Static Blue Line)
              Container(
                width: 2.5,
                color: const Color(0xFF1976D2).withOpacity(0.3),
              ),

              // The Moving Bus
              Align(
                alignment: Alignment(0, _positionAnimation.value),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    size: 12,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    // 3. Future segment
    return Container(width: 2, color: Colors.white10);
  }
}

class LiveSimulationConnector extends StatefulWidget {
  final bool isPassed;
  final bool isLoading;
  final double progress; // 0.0 (at prev stop) to 1.0 (at target stop)

  const LiveSimulationConnector({
    super.key,
    required this.isPassed,
    required this.isLoading,
    required this.progress,
  });

  @override
  State<LiveSimulationConnector> createState() => _LiveSimulationConnectorState();
}

class _LiveSimulationConnectorState extends State<LiveSimulationConnector>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPassed) return Container(width: 2.5, color: const Color(0xFF1976D2));
    if (!widget.isLoading) return Container(width: 2, color: Colors.white10);

    return Stack(
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      children: [
        // 1. THE FLOWING LINE (Background)
        const FlowingLineConnector(isPassed: false, isLoading: true),

        // 2. THE PULSING BUS ICON
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Positioned(
              // Position the bus based on real-world progress
              top: widget.progress * 60, // Adjust 60 based on your row height
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4 * _pulseController.value),
                      blurRadius: 8 * _pulseController.value,
                      spreadRadius: 4 * _pulseController.value,
                    )
                  ],
                ),
                child: const Icon(Icons.directions_bus, size: 10, color: Colors.white),
              ),
            );
          },
        ),
      ],
    );
  }
}
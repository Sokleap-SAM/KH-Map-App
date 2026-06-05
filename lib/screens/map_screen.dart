import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
import 'package:kh_map_app/models/route_stop.dart';
import 'package:kh_map_app/models/transit_route.dart';
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
import 'package:kh_map_app/services/transit_service.dart';
import 'package:kh_map_app/utils/eta.dart';
import 'package:kh_map_app/widgets/map_screen/place_detail_sheet.dart';
import 'package:kh_map_app/widgets/map_screen/search_bar.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/favorite_route.dart';
import '../models/route_plan.dart';
import '../providers/map_provider.dart';
import '../services/auth_service.dart';
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

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final FavoritesService _favoritesService = FavoritesService();
  final FavoriteRoutesService _favoriteRoutesService = FavoriteRoutesService();

  // UI-only state. The data layers (places, line routes, trips, colors) live
  // in MapProvider / TransitProvider.
  double _currentZoom = 13.0;
  final Set<String> _selectedRouteIds = {};
  bool _seededFilterFromRoutes = false;
  final Set<String> _favoritePlaceIds = {};

  /// Pushes the current filter to TransitProvider, which opens/closes the
  /// matching MQTT topic subscriptions. Safe to call repeatedly; the provider
  /// only acts on the diff.
  void _syncMqttSubscriptions() {
    context.read<TransitProvider>().setSubscribedRoutes(
      Set<String>.from(_selectedRouteIds),
    );
  }

  @override
  void initState() {
    super.initState();
    context.read<MapProvider>().init();
    context.read<TransitProvider>().init();
    _loadFavorites();
    AuthService.tokenNotifier.addListener(_onAuthChanged);
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
    } catch (e) {
      debugPrint('Failed to load favorites: $e');
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
      debugPrint('Failed to persist favorite: $e');
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
    _mapController.dispose();
    super.dispose();
  }

  /// Persists [option] (the active route plan option) as a favorite route.
  /// Returns the new favorite's id on success (so the bookmark icon can flip to
  /// its saved state and later remove it), or null on failure.
  Future<String?> _saveFavoriteRoute(RouteOption option) async {
    final provider = context.read<MapProvider>();
    final originPos = provider.routingOrigin;
    final destPos = provider.routingDestination;

    final legs = FavoriteRoutesService.legsFromOption(option);
    if (originPos == null || destPos == null || legs == null) {
      _snack('មិនអាចរក្សាទុកផ្លូវនេះបានទេ');
      return null;
    }

    // A favorite stores a FIXED origin coordinate, so a live "current location"
    // label would be misleading once the user moves. Resolve the saved point to
    // a stable address (falling back to coordinates) in that case.
    final originLabel = provider.routingOriginLabel;
    final originName = (provider.useLiveCurrentOrigin ||
            originLabel == null ||
            originLabel.trim().isEmpty)
        ? await provider.reverseGeocodeLabel(originPos)
        : originLabel;

    final origin = FavoriteRouteEndpoint(name: originName, coordinates: originPos);
    final destination = FavoriteRouteEndpoint(
      name: provider.routingDestinationLabel ?? 'គោលដៅ',
      coordinates: destPos,
    );

    try {
      final saved = await _favoriteRoutesService.add(
        origin: origin,
        destination: destination,
        legs: legs,
        label: '${origin.name} → ${destination.name}',
      );
      _snack('បានរក្សាទុកផ្លូវទៅចំណាំ');
      return saved.id;
    } catch (e) {
      debugPrint('Failed to save favorite route: $e');
      _snack('មិនអាចរក្សាទុកផ្លូវបានទេ');
      return null;
    }
  }

  /// Removes the favorite route saved during this routing view.
  Future<bool> _removeFavoriteRoute(String favoriteId) async {
    try {
      await _favoriteRoutesService.remove(favoriteId);
      _snack('បានលុបផ្លូវចេញពីចំណាំ');
      return true;
    } catch (e) {
      debugPrint('Failed to remove favorite route: $e');
      _snack('មិនអាចលុបផ្លូវបានទេ');
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
    _showPlaceDetail(context, place);
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
                  final label = provider.droppedPinPlace != null
                      ? provider.droppedPinPlace!.split(',').first.trim()
                      : '${pin.latitude.toStringAsFixed(6)}, '
                            '${pin.longitude.toStringAsFixed(6)}';
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

  void _showStopDetail(RouteStop stop, TransitRoute route) {
    final color =
        context.read<TransitProvider>().routeColors[route.id] ?? Colors.blue;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.directions_bus, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.stopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ខ្សែរត់ ${route.code ?? '??'} · Stop ${stop.stopOrder}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (route.name != null) ...[
                const SizedBox(height: 14),
                Text(
                  route.name!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showPlaceDetail(BuildContext context, Place place) {
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
              label: place.name,
              location: LatLng(place.latitude, place.longitude),
            ),
          );
        },
      ),
    );
  }

  /// Looks up a [Trip] by its `tripId` in [TransitProvider.trips] and opens
  /// the existing [_showBusDetails] panel for it.
  ///
  /// Called from the "View" button on each bus segment inside the route info
  /// card. If the matching trip isn't in the provider's cache (it could have
  /// ended, or its route hasn't been subscribed yet so MQTT hasn't surfaced
  /// it), surface a brief snackbar instead of opening an empty panel.
  void _viewBusByTripId(String tripId) {
    final trips = context.read<TransitProvider>().trips;
    final match = trips.where((t) => t.id == tripId).firstOrNull;
    if (match != null) {
      _showBusDetails(match);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live bus details are not available right now.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showBusDetails(Trip trip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
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
                            const Text(
                              "ខ្សែរត់ · ROUTE",
                              style: TextStyle(
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
                              const Text(
                                "ផ្លាកលេខ",
                                style: TextStyle(
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
                        const Expanded(
                          child: _InfoBox(
                            label: "ស្ថានភាព",
                            content: Row(
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
                                const Text(
                                  "ចំណតបន្ទាប់ · NEXT STOP",
                                  style: TextStyle(
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
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "ជ្រើសរើសខ្សែរត់ · SELECT ROUTES",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 15),
                  CheckboxListTile(
                    title: const Text(
                      "បង្ហាញទាំងអស់ (Show All)",
                      style: TextStyle(color: Colors.white),
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
                            "ខ្សែរត់ ${route.code ?? '??'}",
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
            // AUTO-SCROLL LOGIC: Run once when the panel opens
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
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      "ចំណតទាំងអស់ · ALL STOPS",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 50),
                      itemCount: trip.allStops.length,
                      itemBuilder: (context, index) {
                        bool isTarget = index == trip.nextStopIndex;
                        bool isPassed = index < trip.nextStopIndex;
                        bool isLast = index == trip.allStops.length - 1;
                        bool isLinePassed = index < (trip.nextStopIndex - 1);
                        bool isLineLoading = index == (trip.nextStopIndex - 1);

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. THE TIMELINE LANE (Fixed width ensures no "floating")
                              SizedBox(
                                width: 60,
                                child: Column(
                                  children: [
                                    // Area for the Dot
                                    SizedBox(
                                      height:
                                          30, // Centers dot with the first line of text
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
                                                ),
                                              ),
                                      ),
                                    ),
                                    // Area for the Connecting Line
                                    if (!isLast)
                                      Expanded(
                                        child: Center(
                                          child: FlowingLineConnector(
                                            isPassed: isLinePassed,
                                            isLoading: isLineLoading,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // 2. THE STATION NAME
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 40,
                                  ),
                                  child: Text(
                                    trip.allStops[index],
                                    style: TextStyle(
                                      color: isTarget
                                          ? Colors.white
                                          : (isPassed
                                                ? Colors.white70
                                                : Colors.white24),
                                      fontSize: 16,
                                      height: 1.4,
                                      fontWeight: isTarget
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
        return Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "ទិសដៅរត់ · DIRECTIONS",
                style: TextStyle(
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
                  const Text(
                    "ចាប់ផ្តើម: ",
                    style: TextStyle(color: Colors.white54),
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
                  const Text(
                    "គោលដៅ: ",
                    style: TextStyle(color: Colors.white54),
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
              const Center(
                child: Text(
                  "មុខងារនេះនឹងមកដល់ឆាប់ៗនេះ\n(Navigation coming soon)",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white24, fontSize: 12),
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

    // Seed the filter with every route the first time line routes load, so
    // the default view shows all routes. After that, the user owns the set.
    if (!_seededFilterFromRoutes && transitProvider.lineRoutes.isNotEmpty) {
      _seededFilterFromRoutes = true;
      _selectedRouteIds.addAll(transitProvider.lineRoutes.map((r) => r.id));
      // Provider updates must happen outside build — defer to the next frame.
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
            TransitRouteLayer(
              routes: displayRoutes,
              routeStops: transitProvider.routeStops,
              routeColors: transitProvider.routeColors,
              currentZoom: _currentZoom,
              onStopTap: _showStopDetail,
            ),
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
            if (_currentZoom >= 17.0)
              PlaceMarkersLayer(
                places: provider.places,
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
                    MapSearchBar(onPlaceSelected: _focusOnPlace),
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

  @override
  void initState() {
    super.initState();
    _fetchSnapshot();
  }

  Future<void> _fetchSnapshot() async {
    try {
      final snap = await TransitService().fetchTripEta(widget.tripId);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _snapshotLoaded = true;
      });
    } catch (e) {
      debugPrint('_LiveEtaBox: snapshot fetch failed: $e');
      if (!mounted) return;
      setState(() => _snapshotLoaded = true);
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

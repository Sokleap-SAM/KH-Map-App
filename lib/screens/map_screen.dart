import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
import 'package:kh_map_app/models/trip.dart';
import 'package:kh_map_app/providers/transit_provider.dart';
import 'package:kh_map_app/widgets/map/bus_markers_layer.dart';
import 'package:kh_map_app/widgets/map/map_pick_banner.dart';
import 'package:kh_map_app/widgets/map/route_info_card.dart';
import 'package:kh_map_app/widgets/map/route_search_overlay.dart';
import 'package:kh_map_app/widgets/map/routing_overlay_layer.dart';
import 'package:kh_map_app/widgets/map/transit_route_layer.dart';
import 'package:kh_map_app/widgets/map_screen/pin.dart';
import 'package:kh_map_app/widgets/map_screen/place_detail_sheet.dart';
import 'package:kh_map_app/widgets/map_screen/search_bar.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
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

  // UI-only state. The data layers (places, line routes, trips, colors) live
  // in MapProvider / TransitProvider.
  double _currentZoom = 13.0;
  final Set<String> _selectedRouteIds = {};
  bool _seededFilterFromRoutes = false;

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
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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

  void _showPlaceDetail(BuildContext context, Place place) {
    showModalBottomSheet(
      context: context,
      builder: (_) => PlaceDetailSheet(
        place: place,
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
                        _buildInfoBox(
                          "ស្ថានភាព",
                          Row(
                            children: const [
                              Icon(Icons.circle, color: Colors.green, size: 10),
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
                        const SizedBox(width: 10),
                        _buildInfoBox(
                          "ETA",
                          const Text(
                            "~4 min",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Column(
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
                    itemCount: trip.allStops.length,
                    itemBuilder: (context, index) {
                      final isTarget = index == trip.nextStopIndex;
                      final isPassed = index < trip.nextStopIndex;

                      return IntrinsicHeight(
                        child: Row(
                          children: [
                            const SizedBox(width: 30),
                            Column(
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isTarget
                                        ? const Color(0xFF1976D2)
                                        : (isPassed
                                              ? Colors.white24
                                              : Colors.white10),
                                    border: isTarget
                                        ? Border.all(
                                            color: Colors.blue.withAlpha(128),
                                            width: 4,
                                          )
                                        : null,
                                  ),
                                  child: isTarget
                                      ? Center(
                                          child: Container(
                                            width: 4,
                                            height: 4,
                                            decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    color: Colors.white10,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 30),
                                child: Text(
                                  trip.allStops[index],
                                  style: TextStyle(
                                    color: isTarget
                                        ? Colors.white
                                        : (isPassed
                                              ? Colors.white24
                                              : Colors.white38),
                                    fontSize: 16,
                                    fontWeight: isTarget
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
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

  Widget _buildInfoBox(String label, Widget content) {
    return Expanded(
      child: Container(
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
            if (provider.showBusLines && _currentZoom >= 12.0)
              TransitRouteLayer(
                routes: displayRoutes,
                routeStops: transitProvider.routeStops,
                routeColors: transitProvider.routeColors,
              ),
            // State C: routing overlay.
            if (provider.isRoutingActive && provider.activeOption != null)
              RoutingOverlayLayer(option: provider.activeOption!),
            if (_currentZoom >= 12.0)
              BusMarkersLayer(
                trips: displayTrips,
                routeColors: transitProvider.routeColors,
                onBusTap: _showBusDetails,
              ),
            if (_currentZoom >= 15.0)
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
          ),
      ],
    );
  }
}

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
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/map_provider.dart';
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

  // Centralized Khmer normalization to handle variations in spacing and symbols
  String _normalizeKhmer(String s) {
    return s.trim().toLowerCase()
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '') // Zero-width spaces
        .replaceAll(RegExp(r'[|.\-\s]'), '')            // Symbols and standard spaces
        .replaceAll(RegExp(r'\s+'), '');                // Any remaining whitespace
  }

  double _currentZoom = 13.0;
  final Set<String> _selectedRouteIds = {};
  bool _seededFilterFromRoutes = false;

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
    context.read<MapProvider>().addToRecentSearches(place.id);
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

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude, end: destLocation.longitude);
    final zoomTween =
        Tween<double>(begin: _mapController.camera.zoom, end: destZoom);

    final controller = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    final Animation<double> animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
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
    final String name = place.name.toLowerCase();
    
    // Extremely robust check: covers categories or names containing 'bus' or 'stop'
    if (cat.contains('bus') || 
        cat.contains('stop') || 
        cat.contains('transit') || 
        name.contains('bus stop') || 
        name.contains('ចំណត')) {
      debugPrint("Opening specialized Bus Stop panel for: ${place.name}");
      _showBusStopPanel(place);
      return;
    }

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
            final stopName = _normalizeKhmer(stop.name);

            final stopTrips = transit.trips.where((t) {
              final hasStop = t.allStops.any((s) {
                final normS = _normalizeKhmer(s);
                return normS.contains(stopName) || stopName.contains(normS); // Use normalized names for comparison
              });
              final bool isActive = !t.isCompleted && !t.isCancelled;
              return hasStop && isActive; // Only return true if both conditions are met
            }).toList();
            Trip? closestBus;
            int minStopsAway = 999;
            for (var trip in stopTrips) {
              final stopIdx = trip.allStops.indexWhere((s) {
                final normS = _normalizeKhmer(s);
                return normS.contains(stopName) || stopName.contains(normS);
              });

              if (stopIdx != -1 && trip.nextStopIndex <= stopIdx) {
                final away = stopIdx - trip.nextStopIndex; // Calculate stops away
                if (away < minStopsAway) {
                  minStopsAway = away;
                  closestBus = trip;
                }
              }
            }
            final displayTrip = closestBus ?? (stopTrips.isNotEmpty ? stopTrips.first : null);

            // Filter out the closest bus to get "Other" trips
            final otherTrips = stopTrips.where((t) => t.id != displayTrip?.id).toList();

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
                      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                        const Text("ចំណតរថយន្តក្រុង · BUS STOP", style: TextStyle(color: Colors.white70, fontSize: 10)),
                        Text(stop.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
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
                            header: const [
                              SizedBox(height: 20),
                              Text("ការធ្វើដំណើររបស់រថយន្តនេះ · ROUTE ITINERARY",
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                              SizedBox(height: 15),
                            ],
                            trailing: [
                              if (otherTrips.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                const Text("ខ្សែរត់ផ្សេងទៀតដែលឆ្លងកាត់ · OTHER BUS LINES",
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                ...otherTrips.map((t) => _buildStopTripItem(t)),
                              ]
                            ],
                          )
                        : ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (otherTrips.isNotEmpty) ...[
                                const Text("ខ្សែរត់ផ្សេងទៀតដែលឆ្លងកាត់ · OTHER BUS LINES",
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                ...otherTrips.map((t) => _buildStopTripItem(t)),
                              ] else
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40),
                                    child: Text("No active buses at this stop",
                                        style: TextStyle(
                                            color: Colors.white24, fontSize: 12)),
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
        color: Colors.white.withOpacity(0.05),
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
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text("Route ${trip.routeNumber} - ${trip.direction}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        child: Center(child: Text(trip.routeNumber ?? '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
      ),
      title: Text(trip.routeName ?? 'Bus Route', style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Text("To: ${trip.direction}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white12, size: 14),
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
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── FIXED HEADER ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1976D2),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("ខ្សែរត់ · ROUTE", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                                Text(trip.routeNumber ?? 'N/A', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.white.withAlpha(51), borderRadius: BorderRadius.circular(15)),
                              child: Column(
                                children: [
                                  const Text("ផ្លាកលេខ", style: TextStyle(color: Colors.white70, fontSize: 10)),
                                  Text(trip.busNumber ?? '??z', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            const Icon(Icons.directions_bus_filled, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(trip.routeName ?? 'Unknown Route', style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 2),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ── SCROLLABLE CONTENT ────────────────────────────────
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            _buildInfoBox(
                              "ស្ថានភាព",
                              Row(
                                children: const [
                                  Icon(Icons.circle, color: Colors.green, size: 10),
                                  SizedBox(width: 5),
                                  Text("In service", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildInfoBox("ETA", const Text("~4 min", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
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
                                decoration: BoxDecoration(color: const Color(0xFFFFEBD8), borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.bus_alert, color: Color(0xFFE8B67D)),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("ចំណតបន្ទាប់ · NEXT STOP", style: TextStyle(color: Colors.white38, fontSize: 10)),
                                    Text(trip.nextStopName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            _buildActionButton(Icons.list, "All stops", onTap: () {
                              Navigator.pop(context);
                              _showAllStopsPanel(trip);
                            }),
                            const SizedBox(width: 10),
                            _buildActionButton(Icons.map_outlined, "Directions", onTap: () {
                              Navigator.pop(context);
                              _showDirectionsPanel(trip);
                            }),
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

    final List<Place> displayPlaces = provider.places.where((place) {
      final bool isRecent = provider.recentSearchIds.contains(place.id);

      // 1. If it's a recent search, show it from Zoom 10.0 (Far away)
      if (isRecent) return _currentZoom >= 10.0;

      // 2. If it's a normal place, show it from Zoom 14.5 (Close up)
      return _currentZoom >= 16.5;
    }).toList();

    // Seed the filter with every route once they load.
    if (transitProvider.lineRoutes.isNotEmpty && !_seededFilterFromRoutes) {
      final ids = transitProvider.lineRoutes.map((r) => r.id).toList();
      if (ids.isNotEmpty) {
        _selectedRouteIds.addAll(ids);
        _seededFilterFromRoutes = true;
      }
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
                  places: provider.places,
                  currentLocation: provider.currentPosition!,
                  initialDestination: provider.routeSearchDestination!,
                  onClose: () => provider.closeRouteSearch(),
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
    if (oldWidget.currentStopName != widget.currentStopName || oldWidget.trip != widget.trip) {
      _findCurrentStopIndex();
    }
  }

  String _normalizeKhmer(String s) {
    return s.trim().toLowerCase()
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

    final bool newIsScrolledToTop = _internalScrollController.position.pixels == 0;
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
    final targetOffset = headerHeight + (index * itemHeight) - (viewportHeight / 2) + (itemHeight / 2);

    _internalScrollController.animateTo(
      targetOffset.clamp(0.0, _internalScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScrollButtonPress() {
    if (_isScrolledToTop && _currentStopIndex != null && _currentStopIndex != -1) {
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
    if (widget.controller == null) { // Only dispose if we created it
      _internalScrollController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the scroll button should be shown
    bool showScrollButton = false;
    if (widget.currentStopName != null && _currentStopIndex != null && _currentStopIndex != -1) {
      // Always show button if there's a specific stop to track
      showScrollButton = true;
    } else if (!_isScrolledToTop) {
      // Show scroll to top if not at top and no specific stop to track
      showScrollButton = true;
    }

    // Determine the icon for the scroll button
    IconData buttonIcon;
    if (_isScrolledToTop && widget.currentStopName != null && _currentStopIndex != null && _currentStopIndex != -1) {
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
            physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
            itemCount: (widget.header?.length ?? 0) + widget.trip.allStops.length + (widget.trailing?.length ?? 0),
            itemBuilder: (context, index) {
              // Handle Header Widgets
              if (widget.header != null && index < widget.header!.length) {
                return widget.header![index];
              }

              final int stopIndex = index - (widget.header?.length ?? 0);

              // Handle Trailing Widgets
              if (stopIndex >= widget.trip.allStops.length) {
                return widget.trailing![stopIndex - widget.trip.allStops.length];
              }

              // Handle Itinerary Items
              final stopName = widget.trip.allStops[stopIndex];
              bool isTarget = stopIndex == widget.trip.nextStopIndex;
              bool isPassed = stopIndex < widget.trip.nextStopIndex;
              bool isLast = stopIndex == widget.trip.allStops.length - 1;
              bool isLinePassed = stopIndex < (widget.trip.nextStopIndex - 1);
              bool isLineLoading = stopIndex == (widget.trip.nextStopIndex - 1);

              bool isCurrentSelectedStop = widget.currentStopName != null &&
                  (stopName.toLowerCase().contains(widget.currentStopName!.toLowerCase()) ||
                   widget.currentStopName!.toLowerCase().contains(stopName.toLowerCase()));

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
                                            ? Border.all(color: Colors.greenAccent, width: 2)
                                            : null,
                                      ),
                                    ),
                            ),
                          ),
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
                                    : (isPassed ? Colors.white70 : Colors.white24)),
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
              mini: true,
              backgroundColor: const Color(0xFF1976D2),
              onPressed: _handleScrollButtonPress,
              child: Icon(
                buttonIcon,
                color: Colors.white,
              ),
            ),
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
                ).withOpacity(1 - _controller.value),
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

    // 3. Default: show a dim line for future segments
    return Container(width: 2.5, color: Colors.white10);
  }
}
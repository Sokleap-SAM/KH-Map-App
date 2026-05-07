import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_stop.dart';
import 'package:kh_map_app/models/transit_route.dart';
import 'package:kh_map_app/models/trip.dart';
import 'package:kh_map_app/providers/transit_provider.dart';
import 'package:kh_map_app/widgets/map/bus_markers_layer.dart';
import 'package:kh_map_app/widgets/map/transit_route_layer.dart';
import 'package:kh_map_app/widgets/map_screen/Pin.dart';
import 'package:kh_map_app/widgets/map_screen/SearchBar.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';

import '../providers/map_provider.dart';
import '../services/place_service.dart';
import '../services/transit_service.dart';
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
  final PlaceService _placeService = PlaceService();
  final TransitService _transitService = TransitService();

  List<Place> _places = [];
  bool _placesLoading = true;

  List<TransitRoute> _lineRoutes = [];
  Map<String, List<RouteStop>> _routeStops = {};
  Map<String, Color> _routeColors = {};

  static const List<Color> _routePalette = [
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    context.read<MapProvider>().init();
    context.read<TransitProvider>().init();
    _loadPlaces();
    _loadLineRoutes();
  }

  Future<void> _loadPlaces() async {
    try {
      final places = await _placeService.fetchPlaces();
      if (mounted) {
        setState(() {
          _places = places;
          _placesLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint('Failed to load places: $e\n$stack');
      if (mounted) {
        setState(() => _placesLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load places: $e'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                setState(() => _placesLoading = true);
                _loadPlaces();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadLineRoutes() async {
    try {
      final routes = await _transitService.fetchLineRoutes();
      final stopsMap = <String, List<RouteStop>>{};
      final colors = <String, Color>{};
      for (var i = 0; i < routes.length; i++) {
        final route = routes[i];
        stopsMap[route.id] = await _transitService.fetchRouteStops(route.id);
        colors[route.id] = _routePalette[i % _routePalette.length];
      }
      if (mounted) {
        setState(() {
          _lineRoutes = routes;
          _routeStops = stopsMap;
          _routeColors = colors;
        });
      }
    } catch (e) {
      debugPrint('Failed to load line routes: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load bus lines: $e')));
      }
    }
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
    final provider = context.read<MapProvider>();
    provider.dropPin(latLng);
    _showPinSheet();
  }

  void _showPinSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ChangeNotifierProvider.value(
          value: context.read<MapProvider>(),
          child: Consumer<MapProvider>(
            builder: (context, provider, _) {
              if (provider.droppedPin == null) {
                return const SizedBox.shrink();
              }
              return PinInfoSheet(
                latitude: provider.droppedPin!.latitude,
                longitude: provider.droppedPin!.longitude,
                placeName: provider.droppedPinPlace,
                road: provider.droppedPinRoad,
                isLoading: provider.isLoadingPinInfo,
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) {
        context.read<MapProvider>().removePin();
      }
    });
  }

  void _showPlaceDetail(BuildContext context, Place place) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Category: ${place.category?.name ?? 'Uncategorized'}'),
            Text('Rating: ${place.averageRating?.toStringAsFixed(1) ?? 'N/A'}'),
            if (place.photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: place.photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      place.photos[i],
                      width: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
          margin: const EdgeInsets.all(10), // Floating look
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E), // Dark background
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- BLUE HEADER SECTION ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1976D2), // Modern Blue
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
                            color: Colors.white.withOpacity(0.2),
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
                            trip.routeName ?? 'Unknown Route', // "Win-Win Boulevard... -> Veal Sbov..."
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

              // --- DARK BODY SECTION ---
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Row for Status and ETA
                    Row(
                      children: [
                        _buildInfoBox(
                          "ស្ថានភាព",
                          Row(
                            children: [
                              const Icon(
                                Icons.circle,
                                color: Colors.green,
                                size: 10,
                              ),
                              const SizedBox(width: 5),
                              const Text(
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

                    // Next Stop Highlight
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
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
                          Column(
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
                        ],
                      ),
                    ),

                    const SizedBox(height: 15),

                    // Bottom Action Buttons
                    Row(
                      children: [
                        _buildActionButton(Icons.list, "All stops"),
                        const SizedBox(width: 10),
                        _buildActionButton(Icons.map_outlined, "Directions"),
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

  // Helper: Small Grid Boxes
  Widget _buildInfoBox(String label, Widget content) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
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

  // Helper: Outlined Action Buttons
  Widget _buildActionButton(IconData icon, String label) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {},
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

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MapProvider>();

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

    final transitProvider = context.watch<TransitProvider>();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: provider.currentPosition!,
            initialZoom: 17,
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
              routes: _lineRoutes,
              routeStops: _routeStops,
              routeColors: _routeColors,
            ),
            BusMarkersLayer(
              trips: transitProvider.trips,
              routeColors: _routeColors,
              onBusTap: (trip) {
                _showBusDetails(trip);
              },
            ),
            PlaceMarkersLayer(places: _places, onTap: _showPlaceDetail),
            UserLocationMarkerLayer(position: provider.currentPosition!),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                height: MediaQuery.of(context).padding.top,
              ),
              const MapSearchBar(),
            ],
          ),
        ),
        LocateMeButton(
          isLoading: _placesLoading,
          followUser: provider.followUser,
          onPressed: _centerOnUser,
        ),
      ],
    );
  }
}

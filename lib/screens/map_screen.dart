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
          decoration: const BoxDecoration(
            color: Colors.white, // Light modern grey
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 30,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),

              Row(
              children: [
                // LEFT SIDE: Text info (Smaller font sizes)
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ខ្សែរត់លេខ ${trip.routeNumber ?? '??'}",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A2B4C)),
                        ),
                        Text(
                          "ផ្លាកលេខ: ${trip.busNumber}",
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 10),
                        // Smaller badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            "ទៅកាន់: ${trip.direction}",
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                  // RIGHT SIDE: The Animation
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 110,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A2B4C).withOpacity(0.04),
                        borderRadius: const BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Center(
                        child: Transform.scale(
                          scale: 1.4,
                          child: Lottie.asset(
                            'assets/animations/bus_anim.json',
                            repeat: true,
                          ),
                        ),
                      )
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1, indent: 15, endIndent: 15, color: Color(0xFF1A2B4C)),
              const SizedBox(height: 10),

              // Next Stop Card
              Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFFE8B67D), size: 20),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("ចំណតបន្ទាប់ (Next Stop)", style: TextStyle(color: Colors.black38, fontSize: 10)),
                        Text(
                          trip.nextStopName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2B4C)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // Helper for the "Heading to" badge
  Widget _buildMiniBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B4C).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1A2B4C)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A2B4C),
            ),
          ),
        ],
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

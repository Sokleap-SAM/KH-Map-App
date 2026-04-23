import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
import '../providers/transit_provider.dart';
import '../services/place_service.dart';
// import '../services/transit_service.dart';
// import '../widgets/map/bus_markers_layer.dart';
import '../widgets/map/locate_me_button.dart';
import '../widgets/map/place_markers_layer.dart';
// import '../widgets/map/transit_route_layer.dart';
import '../widgets/map/user_location_marker_layer.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final PlaceService _placeService = PlaceService();
  // final TransitService _transitService = TransitService();

  List<Place> _places = [];
  bool _placesLoading = true;

  // List<TransitRoute> _lineRoutes = [];
  // Map<String, List<RouteStop>> _routeStops = {};
  // Map<String, Color> _routeColors = {};

  // static const List<Color> _routePalette = [
  //   Colors.red,
  //   Colors.blue,
  //   Colors.green,
  //   Colors.orange,
  //   Colors.purple,
  //   Colors.cyan,
  //   Colors.pink,
  //   Colors.teal,
  //   Colors.indigo,
  //   Colors.amber,
  // ];

  @override
  void initState() {
    super.initState();
    context.read<MapProvider>().init();
    // context.read<TransitProvider>().init();
    _loadPlaces();
    // _loadLineRoutes();
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

  // Future<void> _loadLineRoutes() async {
  //   try {
  //     final routes = await _transitService.fetchLineRoutes();
  //     final stopsMap = <String, List<RouteStop>>{};
  //     final colors = <String, Color>{};
  //     for (var i = 0; i < routes.length; i++) {
  //       final route = routes[i];
  //       stopsMap[route.id] = await _transitService.fetchRouteStops(route.id);
  //       colors[route.id] = _routePalette[i % _routePalette.length];
  //     }
  //     if (mounted) {
  //       setState(() {
  //         _lineRoutes = routes;
  //         _routeStops = stopsMap;
  //         _routeColors = colors;
  //       });
  //     }
  //   } catch (e) {
  //     debugPrint('Failed to load line routes: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Failed to load bus lines: $e')),
  //       );
  //     }
  //   }
  // }

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
    print('Tapped: lat=${latLng.latitude}, lng=${latLng.longitude}');
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

    // Only show the current user's marker
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
            MarkerLayer(
              markers: [
                Marker(
                  point: provider.currentPosition!,
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer blue circle (accuracy ring)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(60), // 60/255 alpha
                          shape: BoxShape.circle,
                        ),
                      ),
                      // Inner blue dot
                      Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                      // White border for the dot
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton(
            onPressed: _centerOnUser,
            backgroundColor: Colors.white,
            child: Icon(
              provider.followUser
                  ? Icons.my_location
                  : Icons.location_searching,
              color: provider.followUser ? Colors.blue : Colors.grey,
            ),
            // TransitRouteLayer(
            //   routes: _lineRoutes,
            //   routeStops: _routeStops,
            //   routeColors: _routeColors,
            // ),
            // BusMarkersLayer(
            //   trips: transitProvider.trips,
            //   routeColors: const {},
            // ),
            PlaceMarkersLayer(places: _places, onTap: _showPlaceDetail),
            UserLocationMarkerLayer(position: provider.currentPosition!),
          ],
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

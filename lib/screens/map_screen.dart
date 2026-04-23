import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/widgets/map_screen/pin.dart';
import 'package:kh_map_app/widgets/map_screen/searchBar.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
// import '../providers/transit_provider.dart';
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
        // TransitRouteLayer(
        //   routes: _lineRoutes,
        //   routeStops: _routeStops,
        //   routeColors: _routeColors,
        // ),
        // BusMarkersLayer(
        //   trips: transitProvider.trips,
        //   routeColors: const {},
        // )
        LocateMeButton(
          isLoading: _placesLoading,
          followUser: provider.followUser,
          onPressed: _centerOnUser,
        ),
      ],
    );
  }
}

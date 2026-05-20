import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/models/route_search_selection.dart';
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

  // ── Build ─────────────────────────────────────────────────────────────────

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
        // ── Map ───────────────────────────────────────────────────────────
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
            // States A/B: full bus route polylines
            if (provider.showBusLines)
              TransitRouteLayer(
                routes: transitProvider.lineRoutes,
                routeStops: transitProvider.routeStops,
                routeColors: transitProvider.routeColors,
              ),
            // State C: routing overlay
            if (provider.isRoutingActive && provider.activeOption != null)
              RoutingOverlayLayer(option: provider.activeOption!),
            BusMarkersLayer(
              trips: transitProvider.trips,
              routeColors: transitProvider.routeColors,
            ),
            PlaceMarkersLayer(places: provider.places, onTap: _showPlaceDetail),
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
                    const MapSearchBar(),
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
              provider.clearRouting();
              provider.removePin();
            },
          ),
      ],
    );
  }
}

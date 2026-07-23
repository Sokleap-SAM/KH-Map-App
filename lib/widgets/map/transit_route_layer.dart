import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/route_stop.dart';
import '../../models/transit_route.dart';

class TransitRouteLayer extends StatelessWidget {
  const TransitRouteLayer({
    super.key,
    required this.routes,
    required this.routeStops,
    required this.routeColors,
    required this.onStopTap,
    required this.currentZoom,
  });

  final List<TransitRoute> routes;
  final Map<String, List<RouteStop>> routeStops;
  final Map<String, Color> routeColors;
  final void Function(LatLng latLng) onStopTap;
  final double currentZoom;
  /// Concatenates the stored road-snapped segments exactly as-is. Stop
  /// coordinates are sidewalk markers, never part of the line (segments are
  /// stitched continuous server-side). Legacy routes without any segment
  /// geometry fall back to a stop-to-stop line.
  List<LatLng> _buildRoutePath(List<RouteStop> stops) {
    final points = <LatLng>[
      for (final stop in stops)
        if (stop.segmentPath != null) ...stop.segmentPath!,
    ];
    if (points.isEmpty) {
      return [for (final stop in stops) stop.location];
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    final markers = <Marker>[];
    double lineWidth = currentZoom > 14 ? 5.0 : 2.5;
    bool showMarkers = currentZoom > 12.0;

    for (final route in routes) {
      final stops = routeStops[route.id] ?? [];
      final color = routeColors[route.id] ?? Colors.blue;

      final points = _buildRoutePath(stops);
      if (points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: points,
            color: color.withValues(alpha: 0.8),
            strokeWidth: lineWidth,
          ),
        );
      }
      if (showMarkers) {
        for (final stop in stops) {
          bool isZoomedIn = currentZoom >= 15.0;
          double stopSize = isZoomedIn ? 20.0 : 6.0; // Tiny 6px dot when far

          markers.add(
            Marker(
              point: stop.location,
              width: stopSize,
              height: stopSize,
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () => onStopTap(stop.location),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: isZoomedIn ? 2 : 1,
                    ),
                  ),
                  //only show bus icon if zoom in close
                  child: isZoomedIn
                      ? const Icon(
                          Icons.directions_bus,
                          color: Colors.white,
                          size: 10,
                        )
                      : null,
                ),
              ),
            ),
          );
        }
      }
    }

    return Stack(
      children: [
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
}

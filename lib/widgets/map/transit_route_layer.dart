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
    required this.currentZoom,
  });

  final List<TransitRoute> routes;
  final Map<String, List<RouteStop>> routeStops;
  final Map<String, Color> routeColors;
  final double currentZoom;
  List<LatLng> _buildRoutePath(List<RouteStop> stops) {
    final points = <LatLng>[];
    for (final stop in stops) {
      if (stop.segmentPath != null && stop.segmentPath!.isNotEmpty) {
        if (points.isNotEmpty) points.removeLast();
        points.addAll(stop.segmentPath!);
      } else {
        points.add(stop.location);
      }
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    final markers = <Marker>[];
    double lineWidth = currentZoom > 14 ? 5.0 : 2.5;
    bool showMarkers = currentZoom > 12.0;
    bool useDetailedIcons = currentZoom >= 14.5;
    double markerSize = useDetailedIcons ? 22.0 : 8.0;

    for (final route in routes) {
      final stops = routeStops[route.id] ?? [];
      final color = routeColors[route.id] ?? Colors.blue;

      final points = _buildRoutePath(stops);
      if (points.isNotEmpty) {
        polylines.add(
          Polyline(
            points: points, 
            color: color.withOpacity(0.8),
            strokeWidth: lineWidth,
          )
        );
      }
      if (showMarkers) {
        for (final stop in stops) {
          markers.add(
            Marker(
              point: stop.location,
              width: markerSize,
              height: markerSize,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: useDetailedIcons ? 2 : 1,
                  ),
                ),
                //only show bus icon if zoom in close
                child: useDetailedIcons
                    ? const Icon(Icons.directions_bus, color: Colors.white, size: 10)
                    : null,
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
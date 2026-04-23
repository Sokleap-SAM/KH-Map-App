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
  });

  final List<TransitRoute> routes;
  final Map<String, List<RouteStop>> routeStops;
  final Map<String, Color> routeColors;

  /// Builds the full road-aligned path for a route by collecting each stop's
  /// [segmentPath] in order. Falls back to a straight line between stop
  /// locations when [segmentPath] is absent.
  List<LatLng> _buildRoutePath(List<RouteStop> stops) {
    final points = <LatLng>[];
    for (final stop in stops) {
      if (stop.segmentPath != null && stop.segmentPath!.isNotEmpty) {
        // Avoid duplicating the junction point between consecutive segments.
        if (points.isNotEmpty) points.removeLast();
        points.addAll(stop.segmentPath!);
      } else if (stop.stopOrder == 1) {
        // First stop has no segment; just add its location as the start.
        points.add(stop.location);
      } else {
        // No segmentPath: straight line to this stop.
        points.add(stop.location);
      }
    }
    return points;
  }

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];
    final markers = <Marker>[];

    for (final route in routes) {
      final stops = routeStops[route.id] ?? [];
      final color = routeColors[route.id] ?? Colors.blue;

      final points = _buildRoutePath(stops);
      if (points.isNotEmpty) {
        polylines.add(Polyline(points: points, color: color, strokeWidth: 6.0));
      }

      for (final stop in stops) {
        markers.add(
          Marker(
            point: stop.location,
            width: 24,
            height: 24,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 12,
              ),
            ),
          ),
        );
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

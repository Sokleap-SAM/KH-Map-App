import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Result of projecting a point onto a polyline: how far off the path the point
/// is, and how far along the path the nearest point sits.
class PathProjection {
  /// Perpendicular distance in metres from the query point to the path.
  final double distanceMeters;

  /// Distance in metres from the path start to the projected (nearest) point.
  final double alongMeters;

  /// Total length of the path in metres.
  final double totalMeters;

  const PathProjection({
    required this.distanceMeters,
    required this.alongMeters,
    required this.totalMeters,
  });

  /// 0..1 progress of the projected point along the path.
  double get fraction =>
      totalMeters <= 0 ? 0 : (alongMeters / totalMeters).clamp(0.0, 1.0);
}

const double _metersPerDegLat = 111320.0;

/// Projects [p] onto the polyline [path] and reports the nearest point.
///
/// Uses a local equirectangular approximation (metres relative to each edge
/// start, longitude scaled by cos(lat)) — accurate at city scale and far
/// cheaper than great-circle math per edge. Returns null for an empty or
/// single-point path.
PathProjection? projectOntoPath(LatLng p, List<LatLng> path) {
  if (path.length < 2) return null;

  double bestDist = double.infinity;
  double bestAlong = 0;
  double cumulative = 0;

  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];

    // Local planar frame centred on `a`, x = east, y = north, in metres.
    final latScale = math.cos(a.latitude * math.pi / 180);
    double mx(LatLng q) => (q.longitude - a.longitude) * _metersPerDegLat * latScale;
    double my(LatLng q) => (q.latitude - a.latitude) * _metersPerDegLat;

    final bx = mx(b), by = my(b);
    final px = mx(p), py = my(p);

    final segLen2 = bx * bx + by * by;
    double t = segLen2 == 0 ? 0 : (px * bx + py * by) / segLen2;
    t = t.clamp(0.0, 1.0);

    final projX = bx * t, projY = by * t;
    final dx = px - projX, dy = py - projY;
    final dist = math.sqrt(dx * dx + dy * dy);
    final edgeLen = math.sqrt(segLen2);

    if (dist < bestDist) {
      bestDist = dist;
      bestAlong = cumulative + edgeLen * t;
    }
    cumulative += edgeLen;
  }

  return PathProjection(
    distanceMeters: bestDist,
    alongMeters: bestAlong,
    totalMeters: cumulative,
  );
}

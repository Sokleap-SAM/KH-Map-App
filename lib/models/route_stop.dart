import 'package:latlong2/latlong.dart';

import 'place.dart';

class RouteStop {
  final String id;
  final String routeId;
  final String stopId;

  /// Khmer stop name (place `nameInKhmer`).
  final String stopName;

  /// Latin stop name (place `nameInLatin`); null on legacy records.
  final String? stopNameLatin;

  final LatLng location;
  final int stopOrder;
  final double? distanceFromPrevious;
  final int? estimatedTimeFromPrevious;
  // Road-aligned coordinates from the previous stop to this stop.
  // Null for the first stop (stopOrder == 1).
  final List<LatLng>? segmentPath;

  RouteStop({
    required this.id,
    required this.routeId,
    required this.stopId,
    required this.stopName,
    this.stopNameLatin,
    required this.location,
    required this.stopOrder,
    this.distanceFromPrevious,
    this.estimatedTimeFromPrevious,
    this.segmentPath,
  });

  /// Stop name for the active language ('en' → Latin, else Khmer).
  String localizedStopName(String languageCode) =>
      localizedPlaceName(stopName, stopNameLatin, languageCode);

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    final stop = json['stop'] as Map<String, dynamic>;
    final coords = stop['location']['coordinates'] as List;

    List<LatLng>? segmentPath;
    final segment = json['segmentPath'] as Map<String, dynamic>?;
    if (segment != null) {
      final segCoords = segment['coordinates'] as List;
      segmentPath = segCoords.map((c) {
        final pt = c as List;
        return LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
      }).toList();
    }

    return RouteStop(
      id: json['_id'] as String,
      routeId: json['route'] as String,
      stopId: stop['_id'] as String,
      // The place entity renamed `name` → `nameInKhmer`; fall back to the
      // legacy key (and to '') so a stop never crashes route parsing or shows
      // a blank label.
      stopName:
          (stop['nameInKhmer'] ?? stop['name'] ?? stop['nameInLatin'] ?? '')
              as String,
      stopNameLatin: stop['nameInLatin'] as String?,
      location: LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      ),
      stopOrder: json['stopOrder'] as int,
      distanceFromPrevious: (json['distanceFromPrevious'] as num?)?.toDouble(),
      estimatedTimeFromPrevious: json['estimatedTimeFromPrevious'] as int?,
      segmentPath: segmentPath,
    );
  }
}

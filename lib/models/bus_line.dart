import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class BusLine {
  final String id;
  final String lineNumber;
  final String name;
  final String? description;
  final String? colorHex;
  final num? fare;
  final String status;

  /// Full road path for this corridor, drawn as a polyline on the map.
  final List<LatLng> path;

  BusLine({
    required this.id,
    required this.lineNumber,
    required this.name,
    this.description,
    this.colorHex,
    this.fare,
    required this.status,
    required this.path,
  });

  /// Converts the hex color string (e.g. "#FF5733") to a Flutter [Color].
  /// Falls back to blue if absent or unparseable.
  Color get color {
    if (colorHex == null) return Colors.blue;
    try {
      final hex = colorHex!.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  factory BusLine.fromJson(Map<String, dynamic> json) {
    final pathRaw = json['path'] as Map<String, dynamic>?;
    final List<LatLng> pathPoints;
    if (pathRaw != null) {
      final coords = pathRaw['coordinates'] as List;
      pathPoints = coords.map((c) {
        final pt = c as List;
        return LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
      }).toList();
    } else {
      pathPoints = [];
    }

    return BusLine(
      id: json['_id'] as String,
      lineNumber: json['lineNumber'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      colorHex: json['color'] as String?,
      fare: json['fare'] as num?,
      status: json['status'] as String,
      path: pathPoints,
    );
  }
}

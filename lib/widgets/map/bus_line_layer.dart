import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/bus_line.dart';

/// Draws each [BusLine]'s full path geometry as a polyline on the map.
/// The color comes directly from [BusLine.color] (parsed from the API's
/// hex color field), so no external color palette is needed.
class BusLineLayer extends StatelessWidget {
  const BusLineLayer({super.key, required this.lines});

  final List<BusLine> lines;

  @override
  Widget build(BuildContext context) {
    final polylines = lines
        .where((l) => l.path.isNotEmpty)
        .map((l) => Polyline(points: l.path, color: l.color, strokeWidth: 4.0))
        .toList();

    return PolylineLayer(polylines: polylines);
  }
}

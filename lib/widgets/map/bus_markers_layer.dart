import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/trip.dart';

class BusMarkersLayer extends StatelessWidget {
  const BusMarkersLayer({
    super.key,
    required this.trips,
    required this.routeColors,
    required this.onBusTap,
  });

  final List<Trip> trips;
  final Map<String, Color> routeColors;
  final Function(Trip) onBusTap;

  @override
  Widget build(BuildContext context) {
    final visibleTrips = trips
        .where(
          (t) => t.currentLocation != null && !t.isCompleted && !t.isCancelled,
        )
        .toList();

    return MarkerLayer(
      markers: visibleTrips.map((trip) {
        // final color = routeColors[trip.routeId] ?? Colors.blueGrey;
        return Marker(
          point: trip.currentLocation!,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => onBusTap(trip),
            child: Image.asset(
              'assets/images/${trip.busImage}',
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.directions_bus, color: Colors.blue),
            ),
          ),
        );
      }).toList(),
    );
  }
}

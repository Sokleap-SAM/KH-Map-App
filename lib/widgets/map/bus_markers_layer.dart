import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/trip.dart';

class BusMarkersLayer extends StatelessWidget {
  const BusMarkersLayer({
    super.key,
    required this.trips,
    required this.routeColors,
  });

  final List<Trip> trips;
  final Map<String, Color> routeColors;

  @override
  Widget build(BuildContext context) {
    final visibleTrips = trips
        .where(
          (t) => t.currentLocation != null && !t.isCompleted && !t.isCancelled,
        )
        .toList();

    return MarkerLayer(
      markers: visibleTrips.map((trip) {
        print("LOADING IMAGE: assets/images/${trip.busImage}"); 
        // final color = routeColors[trip.routeId] ?? Colors.blueGrey;
        return Marker(
          point: trip.currentLocation!,
          width: 25,
          height: 25,
          child: Image.asset(
            'assets/images/${trip.busImage}',
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.directions_bus,
              color: Colors.blue,
            )
          ),
        );
      }).toList(),
    );
  }
}

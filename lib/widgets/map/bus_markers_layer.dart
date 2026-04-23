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
        final color = routeColors[trip.routeId] ?? Colors.blueGrey;
        return Marker(
          point: trip.currentLocation!,
          width: 36,
          height: 36,
          child: Tooltip(
            message:
                '${trip.routeNumber != null ? 'Route ${trip.routeNumber}' : 'Bus'}'
                ' · ${trip.busNumber ?? trip.busId}'
                ' · Stop ${trip.currentStopIndex + 1}',
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

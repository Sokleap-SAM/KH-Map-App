import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class UserLocationMarkerLayer extends StatelessWidget {
  const UserLocationMarkerLayer({super.key, required this.position});

  final LatLng position;

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: [
        Marker(
          point: position,
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(60),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

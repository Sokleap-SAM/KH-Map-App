import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../utils/category_icon.dart';

class PlaceMarkersLayer extends StatelessWidget {
  const PlaceMarkersLayer({
    super.key,
    required this.places,
    required this.onTap,
  });

  final List<Place> places;
  final void Function(BuildContext context, Place place) onTap;

  @override
  Widget build(BuildContext context) {
    return MarkerLayer(
      markers: places.map((place) {
        final categoryName = place.category?.name;
        return Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 25,
          height: 25,
          child: GestureDetector(
            onTap: () => onTap(context, place),
            child: Container(
              decoration: BoxDecoration(
                color: getColorForCategory(categoryName),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                getIconForCategory(categoryName),
                color: Colors.white,
                size: 15,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

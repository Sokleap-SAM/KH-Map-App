import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../models/place.dart';
import '../../utils/category_icon.dart';

class PlaceMarkersLayer extends StatelessWidget {
  final List<Place> places;
  final List<String> recentSearchIds;
  final double currentZoom;
  final void Function(BuildContext context, Place place) onTap;

  const PlaceMarkersLayer({
    super.key,
    required this.places,
    required this.recentSearchIds,
    required this.currentZoom,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return fm.MarkerLayer(
      markers: places.map((place) { // 'places' is now assumed to be pre-filtered
        final bool isRecent = recentSearchIds.contains(place.id);
        final String? categoryName = place.category?.name;

        // --- PROFESSIONAL SIZING ---
        // Shrunk sizes: 24px for normal, 30px for recent
        final double iconSize = isRecent ? 30.0 : 24.0;
        final bool showName = currentZoom >= 17.0; // Only show text when very close

        return fm.Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 150, // Wide enough to hold text on the side
          height: iconSize,
          // CRUCIAL: Use center alignment so the anchor is the middle of the Stack
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => onTap(context, place),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none, // Allows text to exist outside the small box
              children: [
                // 1. THE CIRCLE ICON (Always stays exactly on the GPS point)
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: getColorForCategory(categoryName),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                  ),
                  child: Icon(
                    getIconForCategory(categoryName),
                    color: Colors.white,
                    size: iconSize * 0.6,
                  ),
                ),

                // 2. THE NAME LABEL (Positioned to the right of the icon)
                if (showName)
                  Positioned(
                    left: iconSize + 4, // Starts right after the circle
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

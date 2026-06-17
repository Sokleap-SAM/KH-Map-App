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

        // Determine if this place should use a specific route color
        final String cat = (categoryName ?? '').toLowerCase();
        final String name = place.name.toLowerCase();
        final bool isBusStop = cat.contains('bus') || 
                               cat.contains('stop') || 
                               cat.contains('transit') || 
                               name.contains('bus stop') || 
                               name.contains('ចំណត');
        final Color? transitColor = isBusStop ? Colors.blue : null;

        // --- PROFESSIONAL SIZING ---
        // Shrunk sizes: 24px for normal, 30px for recent
        final double iconSize = isRecent ? 30.0 : 24.0;
        final bool showName = currentZoom >= 17.0; // Only show text when very close

        return fm.Marker(
          point: LatLng(place.latitude, place.longitude),
          width: iconSize, // The marker box is now exactly the size of the icon
          height: iconSize,
          // This centers the icon exactly on the GPS coordinate
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
                    color: transitColor ?? getColorForCategory(categoryName),
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
                    // Anchored to the center and pushed right
                    left: (iconSize / 2) + 16, 
                    top: -10, // Allows vertical centering room
                    bottom: -10,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          place.name,
                          softWrap: false, // Keep name on one line
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
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

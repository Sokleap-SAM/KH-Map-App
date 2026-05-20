import 'package:latlong2/latlong.dart';

class RouteSearchSelection {
  const RouteSearchSelection({
    required this.label,
    required this.location,
    this.useLiveCurrentLocation = false,
  });

  final String label;
  final LatLng location;
  final bool useLiveCurrentLocation;
}

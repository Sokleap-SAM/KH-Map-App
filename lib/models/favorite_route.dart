import 'package:latlong2/latlong.dart';

/// One endpoint (origin or destination) of a saved favorite route. The backend
/// stores coordinates GeoJSON-style as `[lng, lat]`.
class FavoriteRouteEndpoint {
  final String name;
  final LatLng coordinates;

  const FavoriteRouteEndpoint({required this.name, required this.coordinates});

  factory FavoriteRouteEndpoint.fromJson(Map<String, dynamic> json) {
    final coords = (json['coordinates'] as List?) ?? const [0, 0];
    return FavoriteRouteEndpoint(
      name: (json['name'] as String?) ?? '',
      coordinates: LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'coordinates': [coordinates.longitude, coordinates.latitude],
      };
}

/// A saved favorite transit route. The backend stores only the endpoints
/// (`{ user, label?, origin, destination }`); the actual journey is re-planned
/// on demand by feeding [origin]/[destination] back into the transit planner.
class FavoriteRoute {
  final String id;
  final String? label;
  final FavoriteRouteEndpoint origin;
  final FavoriteRouteEndpoint destination;
  final DateTime savedAt;

  const FavoriteRoute({
    required this.id,
    required this.origin,
    required this.destination,
    required this.savedAt,
    this.label,
  });

  /// Display title — the stored [label] when present, otherwise "A → B".
  String get displayTitle =>
      (label != null && label!.trim().isNotEmpty)
          ? label!
          : '${origin.name} → ${destination.name}';

  factory FavoriteRoute.fromJson(Map<String, dynamic> json) {
    final rawSaved = (json['createdAt'] ?? json['savedAt']) as String?;
    return FavoriteRoute(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      label: json['label'] as String?,
      origin: FavoriteRouteEndpoint.fromJson(
        (json['origin'] as Map<String, dynamic>?) ?? const {},
      ),
      destination: FavoriteRouteEndpoint.fromJson(
        (json['destination'] as Map<String, dynamic>?) ?? const {},
      ),
      savedAt: DateTime.tryParse(rawSaved ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        if (label != null) 'label': label,
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'createdAt': savedAt.toIso8601String(),
      };
}

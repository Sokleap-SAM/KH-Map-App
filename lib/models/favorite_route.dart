import 'package:latlong2/latlong.dart';

import 'route_plan.dart';

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

/// One bus leg of a saved favorite route — the skeleton the backend rebuilds a
/// live plan from. `route`, `boardStop` and `alightStop` are backend ids.
class FavoriteRouteLeg {
  final String route;
  final String boardStop;
  final String alightStop;

  const FavoriteRouteLeg({
    required this.route,
    required this.boardStop,
    required this.alightStop,
  });

  factory FavoriteRouteLeg.fromJson(Map<String, dynamic> json) =>
      FavoriteRouteLeg(
        route: (json['route'] ?? '').toString(),
        boardStop: (json['boardStop'] ?? '').toString(),
        alightStop: (json['alightStop'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'route': route,
        'boardStop': boardStop,
        'alightStop': alightStop,
      };
}

/// A saved favorite transit route (the skeleton document returned by
/// GET /transit/favorites). Live ETAs/segments are fetched separately from
/// GET /transit/favorites/:id/live.
class FavoriteRoute {
  final String id;
  final String? label;
  final FavoriteRouteEndpoint origin;
  final FavoriteRouteEndpoint destination;
  final List<FavoriteRouteLeg> legs;
  final DateTime savedAt;

  const FavoriteRoute({
    required this.id,
    required this.origin,
    required this.destination,
    required this.legs,
    required this.savedAt,
    this.label,
  });

  /// Transfers = bus legs minus one (a single-bus trip has zero transfers).
  int get transferCount => legs.isEmpty ? 0 : legs.length - 1;

  /// Display title — the stored [label] when present, otherwise "A → B".
  String get displayTitle =>
      (label != null && label!.trim().isNotEmpty)
          ? label!
          : '${origin.name} → ${destination.name}';

  factory FavoriteRoute.fromJson(Map<String, dynamic> json) {
    final rawLegs = (json['legs'] as List?) ?? const [];
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
      legs: rawLegs
          .whereType<Map<String, dynamic>>()
          .map(FavoriteRouteLeg.fromJson)
          .toList(),
      savedAt: DateTime.tryParse(rawSaved ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        if (label != null) 'label': label,
        'origin': origin.toJson(),
        'destination': destination.toJson(),
        'legs': legs.map((l) => l.toJson()).toList(),
        'createdAt': savedAt.toIso8601String(),
      };
}

/// The live rebuild returned by GET /transit/favorites/:id/live. `option`
/// shares the exact shape of one element of GET /transit/plan's `options[]`,
/// so it renders through the same widgets.
class FavoriteRouteLive {
  final bool found;
  final String favoriteId;
  final String? label;
  final FavoriteRouteEndpoint origin;
  final FavoriteRouteEndpoint destination;
  final RouteOption option;

  const FavoriteRouteLive({
    required this.found,
    required this.favoriteId,
    required this.origin,
    required this.destination,
    required this.option,
    this.label,
  });

  factory FavoriteRouteLive.fromJson(Map<String, dynamic> json) =>
      FavoriteRouteLive(
        found: (json['found'] as bool?) ?? false,
        favoriteId: (json['favoriteId'] ?? '').toString(),
        label: json['label'] as String?,
        origin: FavoriteRouteEndpoint.fromJson(
          (json['origin'] as Map<String, dynamic>?) ?? const {},
        ),
        destination: FavoriteRouteEndpoint.fromJson(
          (json['destination'] as Map<String, dynamic>?) ?? const {},
        ),
        option: RouteOption.fromJson(
          (json['option'] as Map<String, dynamic>?) ?? const {'segments': []},
        ),
      );
}

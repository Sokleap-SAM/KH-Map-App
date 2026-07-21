import 'package:latlong2/latlong.dart';

import 'place.dart';

/// A named stop within a route plan segment.
class SegmentStop {
  /// Khmer stop name (place `nameInKhmer`).
  final String name;

  /// Latin stop name (place `nameInLatin`); null on legacy records.
  final String? nameLatin;

  final LatLng coordinates;

  /// Backend stop id, when present. Needed to persist a favorite route's
  /// board/alight stops (POST /transit/favorites expects stop ids). Null when
  /// the plan response omits it.
  final String? stopId;

  /// Road-aligned geometry FROM the previous stop TO this stop.
  /// Same structure as [RouteStop.segmentPath] — a GeoJSON LineString
  /// `{"type":"LineString","coordinates":[[lng,lat],...]}` in the backend
  /// response. Null for the first stop of a segment.
  final List<LatLng>? segmentPath;

  SegmentStop({
    required this.name,
    this.nameLatin,
    required this.coordinates,
    this.stopId,
    this.segmentPath,
  });

  /// Stop name for the active language ('en' → Latin, else Khmer).
  String localizedName(String languageCode) =>
      localizedPlaceName(name, nameLatin, languageCode);

  factory SegmentStop.fromJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as List;

    List<LatLng>? segmentPath;
    final seg = json['segmentPath'] as Map<String, dynamic>?;
    if (seg != null) {
      final segCoords = seg['coordinates'] as List;
      segmentPath = segCoords.map((c) {
        final pt = c as List;
        return LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble());
      }).toList();
    }

    return SegmentStop(
      // The /transit/plan response labels segment stops with `name` (a Khmer
      // string); the place rename added `nameInKhmer`. Read `name` too, or
      // every board/alight/walk label comes through blank.
      name: (json['nameInKhmer'] ?? json['name'] ?? json['nameInLatin'] ?? '')
          as String,
      nameLatin: json['nameInLatin'] as String?,
      stopId: (json['stopId'] ?? json['id'] ?? json['_id'])?.toString(),
      // GeoJSON order: [lng, lat]
      coordinates: LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      ),
      segmentPath: segmentPath,
    );
  }
}

/// Identifies the bus route used in a bus segment.
class BusRouteInfo {
  final String id;
  final String? code;
  final String? name;

  BusRouteInfo({required this.id, this.code, this.name});

  factory BusRouteInfo.fromJson(Map<String, dynamic> json) {
    return BusRouteInfo(
      id: (json['id'] ?? json['_id'] ?? '') as String,
      code: json['code'] as String?,
      name: json['name'] as String?,
    );
  }
}

/// One leg of a route plan — either a walk or a bus segment.
class RouteSegment {
  final String type; // 'walk' | 'bus'

  // Walk fields
  final SegmentStop? from;
  final SegmentStop? to;
  final int? distanceMeters;

  /// Road-following coordinates for this walk leg, supplied by the backend.
  /// Empty list means no path data — fall back to a straight line.
  final List<LatLng> path;

  /// True when this walk leg is a cross-route transfer between two bus stops.
  final bool isTransfer;

  // Bus fields
  final BusRouteInfo? route;
  final SegmentStop? boardAt;
  final SegmentStop? alightAt;
  final List<SegmentStop> intermediateStops;
  final int? waitMinutes;

  /// Pure bus ride time in minutes, excluding wait. Equal to [estimatedMinutes].
  final int? rideMinutes;

  /// Total leg duration: [waitMinutes] + [rideMinutes].
  final int? totalLegMinutes;
  final bool? hasLiveEta;

  /// Specific active trip the backend recommends boarding (used to look up
  /// live trip metadata in the bus-detail view).
  final String? tripId;

  /// The bus running [tripId]. Useful for fleet-side lookups.
  final String? busId;

  /// Upcoming arrivals at [boardAt] in minutes from now, sorted ascending.
  final List<int> busEtas;

  /// Convenience shortcut: first entry of [busEtas].
  final int? nextBusInMinutes;

  // Common
  final int? estimatedMinutes;

  RouteSegment({
    required this.type,
    this.from,
    this.to,
    this.distanceMeters,
    this.path = const [],
    this.isTransfer = false,
    this.route,
    this.boardAt,
    this.alightAt,
    this.intermediateStops = const [],
    this.waitMinutes,
    this.rideMinutes,
    this.totalLegMinutes,
    this.hasLiveEta,
    this.tripId,
    this.busId,
    this.busEtas = const [],
    this.nextBusInMinutes,
    this.estimatedMinutes,
  });

  bool get isWalk => type == 'walk';
  bool get isBus => type == 'bus';

  /// Parses a `path` field that may be either a plain GeoJSON coordinate
  /// array `[[lng, lat], ...]` or a GeoJSON LineString geometry object
  /// `{"type":"LineString","coordinates":[[lng,lat],...]}`.  Both formats
  /// come from OSRM / the backend interchangeably.
  static List<LatLng> _parsePath(dynamic raw) {
    if (raw == null) return const [];
    final List coords;
    if (raw is Map) {
      // GeoJSON geometry object
      coords = (raw['coordinates'] as List?) ?? [];
    } else if (raw is List) {
      coords = raw;
    } else {
      return const [];
    }
    if (coords.isEmpty) return const [];
    return coords
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }

  factory RouteSegment.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;

    if (type == 'walk') {
      return RouteSegment(
        type: type,
        from: SegmentStop.fromJson(json['from'] as Map<String, dynamic>),
        to: SegmentStop.fromJson(json['to'] as Map<String, dynamic>),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
        path: _parsePath(json['path']),
        isTransfer: (json['isTransfer'] as bool?) ?? false,
        estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      );
    } else {
      final rawStops = json['intermediateStops'] as List? ?? [];
      final stops = rawStops
          .map((s) => SegmentStop.fromJson(s as Map<String, dynamic>))
          .toList();
      final etasRaw = json['busEtas'] as List? ?? const [];
      return RouteSegment(
        type: type,
        route: BusRouteInfo.fromJson(json['route'] as Map<String, dynamic>),
        boardAt: SegmentStop.fromJson(json['boardAt'] as Map<String, dynamic>),
        alightAt: SegmentStop.fromJson(
          json['alightAt'] as Map<String, dynamic>,
        ),
        intermediateStops: stops,
        distanceMeters: (json['distanceMeters'] as num?)?.toInt(),
        path: _parsePath(json['path']),
        waitMinutes: (json['waitMinutes'] as num?)?.toInt(),
        rideMinutes: (json['rideMinutes'] as num?)?.toInt(),
        totalLegMinutes: (json['totalLegMinutes'] as num?)?.toInt(),
        hasLiveEta: json['hasLiveEta'] as bool?,
        tripId: json['tripId'] as String?,
        busId: json['busId'] as String?,
        busEtas: etasRaw.map((e) => (e as num).toInt()).toList(),
        nextBusInMinutes: (json['nextBusInMinutes'] as num?)?.toInt(),
        estimatedMinutes: (json['estimatedMinutes'] as num?)?.toInt(),
      );
    }
  }
}

/// One route option returned by GET /transit/plan.
///
/// The API returns up to five options ranked by travel time, with dynamic
/// labels: Fastest / Fast / Average / Slower / Slowest.
class RouteOption {
  /// 'fastest' | 'fast' | 'average' | 'slower' | 'slowest' | 'walk'
  final String type;

  /// Human label matching [type]: 'Fastest' / 'Fast' / 'Average' / 'Slower' /
  /// 'Slowest' / 'Walking'.
  final String label;

  final int totalEstimatedMinutes;
  final int totalDistanceMeters;
  final int totalWalkMeters;
  final int transferCount;

  final String? warning;
  final List<RouteSegment> segments;

  RouteOption({
    required this.type,
    required this.label,
    required this.totalEstimatedMinutes,
    required this.totalDistanceMeters,
    required this.totalWalkMeters,
    required this.transferCount,
    this.warning,
    required this.segments,
  });

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    return RouteOption(
      type: (json['type'] as String?) ?? 'average',
      label: (json['label'] as String?) ?? 'Route',
      totalEstimatedMinutes:
          (json['totalEstimatedMinutes'] as num?)?.toInt() ?? 0,
      totalDistanceMeters: (json['totalDistanceMeters'] as num?)?.toInt() ?? 0,
      totalWalkMeters: (json['totalWalkMeters'] as num?)?.toInt() ?? 0,
      transferCount: (json['transferCount'] as num?)?.toInt() ?? 0,
      warning: json['warning'] as String?,
      segments: (json['segments'] as List)
          .map((s) => RouteSegment.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// The full result from GET /transit/plan.
class RoutePlanResult {
  final bool found;

  /// The plan mode returned by the server: "walk" | "transit".
  final String type;

  final List<RouteOption> options;

  /// Human-readable explanation present only when [found] is false.
  final String? message;

  RoutePlanResult({
    required this.found,
    required this.type,
    required this.options,
    this.message,
  });

  factory RoutePlanResult.fromJson(Map<String, dynamic> json) {
    final found = json['found'] as bool;
    final type = (json['type'] as String?) ?? 'transit';
    if (!found) {
      return RoutePlanResult(
        found: false,
        type: type,
        options: [],
        message: json['message'] as String?,
      );
    }
    return RoutePlanResult(
      found: true,
      type: type,
      options: (json['options'] as List)
          .map((o) => RouteOption.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}

import 'package:latlong2/latlong.dart';

/// Lifecycle states of a trip (`TripStatus`).
class TripStatuses {
  static const String scheduled = 'scheduled';
  static const String inProgress = 'in-progress';
  static const String completed = 'completed';
  static const String cancelled = 'cancelled';

  static const List<String> all = [
    scheduled,
    inProgress,
    completed,
    cancelled,
  ];

  /// The two states `/transit/trips/active` returns.
  static const List<String> active = [scheduled, inProgress];

  const TripStatuses._();
}

class Trip {
  final String id;
  final String routeId;
  final String? routeName;
  final String? routeNumber;
  final String busId;
  final String? busNumber;
  final String status;
  final int currentStopIndex;
  final int nextStopIndex;
  final LatLng? currentLocation;
  final int passengerCount;
  final double? bearing;
  final String busImage;
  final String nextStopName;
  final String direction;
  final List<String> allStops;

  // Live-position fields. Populated from MQTT updates, null until the first
  // position message arrives for a given trip.
  final double? heading;
  final double? speed;
  final DateTime? recordedAt;

  /// Epoch-ms wall-clock departure time for parked buses. Carried by both
  /// the `/transit/trips/:id/eta` snapshot and MQTT position messages whose
  /// `status == 'scheduled'`. Absent once the bus is moving.
  final int? notDepartingUntilMs;

  /// Server-computed ETA from the one-shot `/transit/trips/:id/eta` snapshot.
  /// Not refreshed by MQTT — once we have live position + speed, the UI
  /// re-derives ETA locally via [etaToNextStopSeconds].
  final int? etaSeconds;

  // ── Admin/management fields ───────────────────────────────────────────────
  // Unused by the rider map; read by the admin trip screens.

  final String? busLicensePlate;

  /// Stamped only when a driver *starts* the trip, so it stays null on a
  /// scheduled trip even when the bus has a driver.
  final String? driverId;

  /// The bus's assigned driver — who *will* drive this trip. For a scheduled
  /// trip this is the only link that exists; [driverId] is still null.
  final String? busAssignedDriverId;

  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? createdAt;

  Trip({
    required this.id,
    required this.routeId,
    this.routeName,
    this.routeNumber,
    required this.busId,
    this.busNumber,
    required this.status,
    required this.currentStopIndex,
    required this.nextStopIndex,
    this.currentLocation,
    required this.passengerCount,
    this.bearing,
    required this.busImage,
    required this.nextStopName,
    required this.direction,
    required this.allStops,
    this.heading,
    this.speed,
    this.recordedAt,
    this.notDepartingUntilMs,
    this.etaSeconds,
    this.busLicensePlate,
    this.driverId,
    this.busAssignedDriverId,
    this.startedAt,
    this.completedAt,
    this.createdAt,
  });

  Trip copyWith({
    int? currentStopIndex,
    int? nextStopIndex,
    LatLng? currentLocation,
    String? nextStopName,
    double? heading,
    double? speed,
    DateTime? recordedAt,
    int? notDepartingUntilMs,
    int? etaSeconds,
  }) {
    return Trip(
      id: id,
      routeId: routeId,
      routeName: routeName,
      routeNumber: routeNumber,
      busId: busId,
      busNumber: busNumber,
      status: status,
      currentStopIndex: currentStopIndex ?? this.currentStopIndex,
      nextStopIndex: nextStopIndex ?? this.nextStopIndex,
      currentLocation: currentLocation ?? this.currentLocation,
      passengerCount: passengerCount,
      busImage: busImage,
      nextStopName: nextStopName ?? this.nextStopName,
      direction: direction,
      allStops: allStops,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      recordedAt: recordedAt ?? this.recordedAt,
      notDepartingUntilMs: notDepartingUntilMs ?? this.notDepartingUntilMs,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      // Not patchable by MQTT, but must be carried forward — this runs on every
      // position message, and anything omitted here is silently dropped.
      busLicensePlate: busLicensePlate,
      driverId: driverId,
      busAssignedDriverId: busAssignedDriverId,
      startedAt: startedAt,
      completedAt: completedAt,
      createdAt: createdAt,
    );
  }

  bool get isScheduled => status == 'scheduled';
  bool get isInProgress => status == 'in-progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  factory Trip.fromJson(Map<String, dynamic> json) {
    // route can be a populated object or a bare string ID. It can also be
    // null when the referenced doc was deleted — `null as String` throws, and
    // because the whole list is parsed in one map() a single orphan used to
    // blank every bus on the map. Degrade to '' instead: such a trip simply
    // fails the route filter rather than taking the other trips down with it.
    final routeRaw = json['route'];
    String routeId;
    String? routeName;
    String? routeCode;
    if (routeRaw is Map) {
      routeId = routeRaw['_id'] as String? ?? '';
      routeName = routeRaw['name'] as String?;
      routeCode = routeRaw['code'] as String?;
    } else {
      routeId = routeRaw as String? ?? '';
    }

    // bus can be a populated object, a bare string ID, or null — a scheduled
    // trip with no bus assigned yet is a normal state, not corrupt data.
    final busRaw = json['bus'];
    String busId;
    String? busNumberFromObj;
    String? busLicensePlate;
    String? busAssignedDriverId;
    if (busRaw is Map) {
      busId = busRaw['_id'] as String? ?? '';
      busNumberFromObj = busRaw['busNumber'] as String?;
      busLicensePlate = busRaw['licensePlate'] as String?;
      final assigned = busRaw['assignedDriverId'];
      busAssignedDriverId = assigned is Map
          ? assigned['_id'] as String?
          : assigned as String?;
    } else {
      busId = busRaw as String? ?? '';
    }

    // Stamped only when a driver starts the trip; may be expanded or a bare id.
    final driverRaw = json['driver'];
    final driverId = driverRaw is Map
        ? driverRaw['_id'] as String?
        : driverRaw as String?;

    DateTime? parseDate(String key) {
      final raw = json[key] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    }

    LatLng? currentLocation;
    final loc = json['currentLocation'] as Map<String, dynamic>?;
    if (loc != null) {
      final coords = loc['coordinates'] as List;
      currentLocation = LatLng(
        (coords[1] as num).toDouble(),
        (coords[0] as num).toDouble(),
      );
    }

    final double? bearing = (json['bearing'] as num?)?.toDouble();

    return Trip(
      id: json['_id'] as String,
      routeId: routeId,
      routeName: routeName,
      routeNumber: routeCode ?? '??',

      // 2. Bus Number (Check if it's inside 'bus' object)
      busNumber: busNumberFromObj ?? json['busNumber'] ?? 'N/A',

      // 3. Next Stop Name
      nextStopName: json['nextStopName'] ?? 'N/A',
      busId: busId,
      status: json['status'] as String,
      currentStopIndex: (json['currentStopIndex'] as int?) ?? 0,
      nextStopIndex: (json['nextStopIndex'] as int?) ?? 1,
      currentLocation: currentLocation,
      passengerCount: (json['passengerCount'] as int?) ?? 0,
      bearing: bearing,
      busImage: _resolveBusImage(bearing, json['busImage'] as String?),
      direction: json['direction'] ?? 'N/A',
      allStops: List<String>.from(json['allStops'] ?? []),
      notDepartingUntilMs: (json['notDepartingUntilMs'] as num?)?.toInt(),
      etaSeconds: (json['etaSeconds'] as num?)?.toInt(),
      busLicensePlate: busLicensePlate,
      driverId: driverId,
      busAssignedDriverId: busAssignedDriverId,
      startedAt: parseDate('startedAt'),
      completedAt: parseDate('completedAt'),
      createdAt: parseDate('createdAt'),
    );
  }

  Map<String, dynamic> toJsonForBearingUpdate() {
    return {
      '_id': id,
      'route': {'_id': routeId, 'name': routeName, 'code': routeNumber},
      'bus': {'_id': busId, 'busNumber': busNumber},
      'status': status,
      'currentStopIndex': currentStopIndex,
      'nextStopIndex': nextStopIndex,
      'currentLocation': currentLocation != null
          ? {
              'coordinates': [
                currentLocation!.longitude,
                currentLocation!.latitude,
              ],
            }
          : null,
      'passengerCount': passengerCount,
      'nextStopName': nextStopName,
      'direction': direction,
      'allStops': allStops,
      'busImage': busImage,
    };
  }

  static String _resolveBusImage(double? bearing, String? fallback) {
    if (bearing == null) return fallback ?? 'bus_go_right.png';

    // Normalize bearing to 0-359 degrees
    // 0 is North, 90 is East, 180 is South, 270 is West
    final double b = (bearing % 360 + 360) % 360;

    // Upward/Eastward movement uses Right image, Downward/Westward uses Left image
    if (b >= 0 && b < 180) {
      return 'bus_go_right.png';
    } else {
      return 'bus_go_left.png';
    }
  }
}

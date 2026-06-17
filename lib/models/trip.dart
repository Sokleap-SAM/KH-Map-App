import 'package:latlong2/latlong.dart';

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
  });

  bool get isScheduled => status == 'scheduled';
  bool get isInProgress => status == 'in-progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  factory Trip.fromJson(Map<String, dynamic> json) {
    print("DEBUG TRIP JSON: $json");
    // route can be a populated object or a bare string ID
    final routeRaw = json['route'];
    String routeId;
    String? routeName;
    String? routeNumber;
    if (routeRaw is Map) {
      routeId = routeRaw['_id'] as String;
      routeName = routeRaw['name'] as String?;
      routeNumber = routeRaw['routeNumber'] as String?;
    } else {
      routeId = routeRaw as String;
    }

    // bus can be a populated object or a bare string ID
    final busRaw = json['bus'];
    String busId;
    String? busNumber;
    if (busRaw is Map) {
      busId = busRaw['_id'] as String;
      busNumber = busRaw['busNumber'] as String?;
    } else {
      busId = busRaw as String;
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
      routeNumber: json['route']?['code'] ?? json['routeNumber'] ?? '??',
      busNumber: json['bus']?['busNumber'] ?? json['busNumber'] ?? 'N/A',
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
          ? {'coordinates': [currentLocation!.longitude, currentLocation!.latitude]} 
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

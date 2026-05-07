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
  final String busImage;
  final String nextStopName;
  final String direction;

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
    required this.busImage,
    required this.nextStopName,
    required this.direction,
  });

  bool get isScheduled => status == 'scheduled';
  bool get isInProgress => status == 'in-progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  factory Trip.fromJson(Map<String, dynamic> json) {
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

    return Trip(
      id: json['_id'] as String,
      routeId: routeId,
      routeName: routeName,
      routeNumber: json['routeNumber'] as String? ?? '??',
      busId: busId,
      busNumber: json['busNumber'] as String? ?? 'N/A',
      status: json['status'] as String,
      currentStopIndex: (json['currentStopIndex'] as int?) ?? 0,
      nextStopIndex: (json['nextStopIndex'] as int?) ?? 1,
      currentLocation: currentLocation,
      passengerCount: (json['passengerCount'] as int?) ?? 0,
      busImage: json['busImage'] as String? ?? 'bus_go_right.png',
      nextStopName: json['nextStopName'] ?? 'N/A',
      direction: json['direction'] ?? 'N/A',
    );
  }
}

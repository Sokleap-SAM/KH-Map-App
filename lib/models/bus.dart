/// Fleet status (`BusStatus`). A retired bus is normally moved to
/// [outOfService] rather than deleted, so trip history stays readable.
class BusStatuses {
  static const String inService = 'in-service';
  static const String outOfService = 'out-of-service';
  static const String maintenance = 'maintenance';

  static const List<String> all = [inService, outOfService, maintenance];

  const BusStatuses._();
}

/// A bus from `/transit/buses` — a plain Mongo document, unlike Trip, which
/// arrives enriched with live Redis state.
class Bus {
  final String id;
  final String busNumber;
  final String licensePlate;
  final int capacity;
  final String status;

  /// Driver currently assigned to this bus, or null when it's free.
  ///
  /// Never write this directly — `PATCH /users/admin/drivers/:id/assign-bus`
  /// owns it, and keeps `User.assignedBusId` in sync on the other side.
  final String? assignedDriverId;

  final DateTime? createdAt;

  const Bus({
    required this.id,
    required this.busNumber,
    required this.licensePlate,
    required this.capacity,
    required this.status,
    this.assignedDriverId,
    this.createdAt,
  });

  bool get isAssigned =>
      assignedDriverId != null && assignedDriverId!.isNotEmpty;
  bool get isInService => status == BusStatuses.inService;

  factory Bus.fromJson(Map<String, dynamic> json) {
    // The relation may come back expanded or as a bare id.
    final driverRaw = json['assignedDriverId'] ?? json['assignedDriver'];
    String? assignedDriverId;
    if (driverRaw is Map) {
      assignedDriverId = driverRaw['_id'] as String?;
    } else if (driverRaw is String && driverRaw.isNotEmpty) {
      assignedDriverId = driverRaw;
    }

    final rawCreated = json['createdAt'] as String?;

    return Bus(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      busNumber: (json['busNumber'] as String?) ?? '',
      licensePlate: (json['licensePlate'] as String?) ?? '',
      // Read as num: JSON 25 decodes to int but 25.0 to double, and a direct
      // `as int` cast throws on the latter.
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? BusStatuses.inService,
      assignedDriverId: assignedDriverId,
      createdAt: rawCreated == null ? null : DateTime.tryParse(rawCreated),
    );
  }
}

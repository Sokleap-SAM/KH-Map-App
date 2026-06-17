/// Subset of `GET /users/profile` we need on the driver shell.
/// `assignedBusId` is required to filter trips client-side per the
/// driver brief (open question #1 — server-side filter may be added later).
class DriverProfile {
  final String id;
  final String name;
  final String role;
  final String? assignedBusId;
  final String? assignedBusNumber;

  const DriverProfile({
    required this.id,
    required this.name,
    required this.role,
    this.assignedBusId,
    this.assignedBusNumber,
  });

  bool get hasAssignedBus =>
      assignedBusId != null && assignedBusId!.isNotEmpty;

  DriverProfile copyWith({String? assignedBusId, String? assignedBusNumber}) {
    return DriverProfile(
      id: id,
      name: name,
      role: role,
      assignedBusId: assignedBusId ?? this.assignedBusId,
      assignedBusNumber: assignedBusNumber ?? this.assignedBusNumber,
    );
  }

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final assignedRaw = json['assignedBus'] ?? json['assignedBusId'];
    String? assignedBusId;
    String? assignedBusNumber;
    if (assignedRaw is Map) {
      assignedBusId = assignedRaw['_id'] as String?;
      assignedBusNumber = assignedRaw['busNumber'] as String?;
    } else if (assignedRaw is String) {
      assignedBusId = assignedRaw;
    }
    return DriverProfile(
      id: (json['_id'] ?? json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      role: (json['role'] ?? 'user') as String,
      assignedBusId: assignedBusId,
      assignedBusNumber: assignedBusNumber,
    );
  }
}

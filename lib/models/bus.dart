class Bus {
  final String id;
  final String busNumber;
  final String licensePlate;
  final int capacity;
  final String status;

  Bus({
    required this.id,
    required this.busNumber,
    required this.licensePlate,
    required this.capacity,
    required this.status,
  });

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: json['_id'] as String,
      busNumber: json['busNumber'] as String,
      licensePlate: json['licensePlate'] as String,
      capacity: json['capacity'] as int,
      status: (json['status'] as String?) ?? 'active',
    );
  }
}

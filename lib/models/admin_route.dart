/// Row in the admin route list (`GET /transit/routes`).
///
/// The backend may or may not include a stop count; we read whichever of the
/// common field names is present and leave it null otherwise so the UI can
/// show a placeholder instead of a wrong number.
class AdminRoute {
  final String id;
  final String? name;
  final String? code;
  final bool isLine;
  final String status;
  final int? stopCount;

  const AdminRoute({
    required this.id,
    required this.name,
    required this.code,
    required this.isLine,
    required this.status,
    required this.stopCount,
  });

  factory AdminRoute.fromJson(Map<String, dynamic> json) {
    int? count;
    final rawCount = json['stopCount'] ??
        json['stopsCount'] ??
        json['numStops'] ??
        json['stopsTotal'];
    if (rawCount is num) {
      count = rawCount.toInt();
    } else {
      // Some shapes embed the stops array directly.
      final stops = json['stops'] ?? json['routeStops'];
      if (stops is List) count = stops.length;
    }

    return AdminRoute(
      id: json['_id'] as String,
      name: json['name'] as String?,
      code: json['code'] as String?,
      isLine: (json['isLine'] as bool?) ?? false,
      status: (json['status'] as String?) ?? 'unknown',
      stopCount: count,
    );
  }
}

class TransitRoute {
  final String id;
  final bool isLine;
  final String? code;
  final String? name;
  final String? description;
  final String status;
  final String? color;
  final String? direction;

  TransitRoute({
    required this.id,
    required this.isLine,
    this.code,
    this.name,
    this.description,
    required this.status,
    this.color,
    this.direction,
  });

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['_id'] as String,
      isLine: (json['isLine'] as bool?) ?? false,
      code: json['code'] as String?,
      name: json['name'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
      color: json['color'] as String?,
      direction: json['direction'] as String?,
    );
  }
}

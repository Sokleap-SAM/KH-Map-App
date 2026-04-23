class TransitRoute {
  final String id;
  final bool isLine;
  final String? code;
  final String? name;
  final String? description;
  final String status;

  TransitRoute({
    required this.id,
    required this.isLine,
    this.code,
    this.name,
    this.description,
    required this.status,
  });

  factory TransitRoute.fromJson(Map<String, dynamic> json) {
    return TransitRoute(
      id: json['_id'] as String,
      isLine: (json['isLine'] as bool?) ?? false,
      code: json['code'] as String?,
      name: json['name'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String,
    );
  }
}

class PlaceCategory {
  final String id;
  final String name;

  PlaceCategory({required this.id, required this.name});

  factory PlaceCategory.fromJson(Map<String, dynamic> json) {
    return PlaceCategory(
      id: json['_id'] as String,
      name: json['name'] as String,
    );
  }
}

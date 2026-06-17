import 'place_category.dart';

class Place {
  final String id;
  final String name;
  final PlaceCategory? category;
  final double longitude;
  final double latitude;
  final double? averageRating;
  final int? ratingCount;
  final List<String> photos;

  Place({
    required this.id,
    required this.name,
    this.category,
    required this.longitude,
    required this.latitude,
    this.averageRating,
    this.ratingCount,
    required this.photos,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    final coords = json['location']['coordinates'] as List;
    return Place(
      id: json['_id'] as String,
      name: json['name'] as String,
      // `category` is a populated object on list/detail responses, but only a
      // raw id string on the create response — guard for both.
      category: json['category'] is Map<String, dynamic>
          ? PlaceCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      longitude: (coords[0] as num).toDouble(),
      latitude: (coords[1] as num).toDouble(),
      averageRating: (json['averageRating'] as num?)?.toDouble(),
      ratingCount: json['ratingCount'] as int?,
      photos: List<String>.from(json['photos'] as List? ?? []),
    );
  }
}

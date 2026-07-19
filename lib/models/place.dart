import 'place_category.dart';

class Place {
  final String id;

  /// Primary Khmer name (backend field `nameInKhmer`, formerly `name`).
  final String nameInKhmer;

  /// Romanized/Latin name (backend field `nameInLatin`). Required by the
  /// backend alongside [nameInKhmer].
  final String nameInLatin;

  final PlaceCategory? category;
  final double longitude;
  final double latitude;
  final double? averageRating;
  final int? ratingCount;
  final List<String> photos;

  Place({
    required this.id,
    required this.nameInKhmer,
    required this.nameInLatin,
    this.category,
    required this.longitude,
    required this.latitude,
    this.averageRating,
    this.ratingCount,
    required this.photos,
  });

  /// The name shown throughout the UI. The app is Khmer-first, so this is the
  /// Khmer name. Kept as a convenience alias so display code doesn't need to
  /// know which localized field to read.
  String get name => nameInKhmer;

  factory Place.fromJson(Map<String, dynamic> json) {
    final coords = json['location']['coordinates'] as List;
    return Place(
      id: json['_id'] as String,
      // Backend renamed `name` → `nameInKhmer`; fall back to the legacy key so
      // an older/mixed response still parses.
      nameInKhmer: (json['nameInKhmer'] ?? json['name']) as String,
      // Required by the backend; fall back to the Khmer name so a legacy
      // record that predates the field still parses instead of throwing.
      nameInLatin:
          (json['nameInLatin'] ?? json['nameInKhmer'] ?? json['name'])
              as String,
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

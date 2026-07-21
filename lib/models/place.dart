import 'place_category.dart';

/// Picks the display name for [languageCode]: 'en' → [latin], anything else →
/// [khmer]. Falls back to [khmer] when the Latin name is missing/empty (legacy
/// records), and to [latin] when the Khmer name is empty, so the UI never
/// shows a blank label. Shared by every model that carries a place/stop name.
String localizedPlaceName(String khmer, String? latin, String languageCode) {
  if (languageCode == 'en') {
    if (latin != null && latin.isNotEmpty) return latin;
    return khmer;
  }
  return khmer.isNotEmpty ? khmer : (latin ?? '');
}

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
  /// Khmer name. Kept as a convenience alias so display code that isn't yet
  /// language-aware keeps working. Prefer [localizedName] for user-facing text.
  String get name => nameInKhmer;

  /// The name to show for the given [languageCode] ('en' → Latin name,
  /// anything else → Khmer), with fallbacks so the label is never blank.
  String localizedName(String languageCode) =>
      localizedPlaceName(nameInKhmer, nameInLatin, languageCode);

  factory Place.fromJson(Map<String, dynamic> json) {
    final coords = json['location']['coordinates'] as List;
    return Place(
      id: json['_id'] as String,
      // Backend renamed `name` → `nameInKhmer`; fall back to the legacy key so
      // an older/mixed response still parses.
      nameInKhmer: (json['nameInKhmer']) as String,
      // Required by the backend; fall back to the Khmer name so a legacy
      // record that predates the field still parses instead of throwing.
      nameInLatin: (json['nameInLatin'] ?? json['nameInKhmer']) as String,
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

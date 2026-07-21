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

  /// Approval state of the place: 'pending', 'approved' or 'rejected'.
  /// Legacy/admin places that predate the approval workflow report 'approved'.
  final String status;

  /// When the place (or request) was created, when the backend includes it.
  final DateTime? createdAt;

  /// When an admin approved/rejected this request. Only the admin review-log
  /// endpoint populates this; null everywhere else.
  final DateTime? reviewedAt;

  /// Display name of the admin who reviewed the request, when populated.
  final String? reviewedByName;

  /// Display name of the user who submitted the request, when populated.
  final String? createdByName;

  /// The admin's explanation for a rejection, so the submitter can see why and
  /// fix/re-submit. Only set on rejected requests; null otherwise.
  final String? rejectionReason;

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
    this.status = 'approved',
    this.createdAt,
    this.reviewedAt,
    this.reviewedByName,
    this.createdByName,
    this.rejectionReason,
  });

  /// The name shown throughout the UI. The app is Khmer-first, so this is the
  /// Khmer name. Kept as a convenience alias so display code that isn't yet
  /// language-aware keeps working. Prefer [localizedName] for user-facing text.
  String get name => nameInKhmer;

  /// The name to show for the given [languageCode] ('en' → Latin name,
  /// anything else → Khmer), with fallbacks so the label is never blank.
  String localizedName(String languageCode) =>
      localizedPlaceName(nameInKhmer, nameInLatin, languageCode);

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory Place.fromJson(Map<String, dynamic> json) {
    final coords = json['location']['coordinates'] as List;
    return Place(
      id: json['_id'] as String,
      // Backend renamed `name` → `nameInKhmer`; fall back to the legacy key so
      // an older/mixed response still parses.
      nameInKhmer: (json['nameInKhmer'] ?? json['name']) as String,
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
      status: json['status'] as String? ?? 'approved',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      reviewedAt: DateTime.tryParse(json['reviewedAt']?.toString() ?? ''),
      // `reviewedBy`/`createdBy` are populated `{ _id, name }` objects on the
      // review-log response and absent/null elsewhere — guard for both.
      reviewedByName: json['reviewedBy'] is Map<String, dynamic>
          ? (json['reviewedBy'] as Map<String, dynamic>)['name'] as String?
          : null,
      createdByName: json['createdBy'] is Map<String, dynamic>
          ? (json['createdBy'] as Map<String, dynamic>)['name'] as String?
          : null,
      rejectionReason: (json['rejectionReason'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['rejectionReason'] as String).trim()
          : null,
    );
  }
}

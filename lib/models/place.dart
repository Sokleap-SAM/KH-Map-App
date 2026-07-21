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
    required this.name,
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

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

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

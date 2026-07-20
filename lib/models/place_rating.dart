/// A single user review for a place: a star score (1–5), an optional comment,
/// and optional photos the reviewer attached. Returned by
/// `GET /places/:placeId/ratings`.
class PlaceRating {
  final String id;
  final String? userId;
  final String userName;
  final String? comment;
  final double score;
  final List<String> photos; // remote (Cloudinary) URLs
  final DateTime? createdAt;

  const PlaceRating({
    required this.id,
    required this.userName,
    required this.score,
    required this.photos,
    this.userId,
    this.comment,
    this.createdAt,
  });

  /// First letter of the reviewer's name, for the avatar fallback circle.
  String get initial =>
      userName.trim().isEmpty ? '?' : userName.trim()[0].toUpperCase();

  factory PlaceRating.fromJson(Map<String, dynamic> json) {
    // `userId` is a populated `{ _id, name }` object on the list response, but
    // can also arrive as a plain id string — guard for both.
    final rawUser = json['userId'];
    String? userId;
    String userName = 'Anonymous';
    if (rawUser is Map<String, dynamic>) {
      userId = rawUser['_id']?.toString();
      final name = rawUser['name']?.toString().trim();
      if (name != null && name.isNotEmpty) userName = name;
    } else if (rawUser != null) {
      userId = rawUser.toString();
    }

    final rawComment = json['comment']?.toString().trim();

    return PlaceRating(
      id: json['_id']?.toString() ?? '',
      userId: userId,
      userName: userName,
      comment: (rawComment == null || rawComment.isEmpty) ? null : rawComment,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      photos:
          (json['photos'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }
}

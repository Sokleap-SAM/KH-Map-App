import 'place.dart';

/// A single user contribution: a rating + optional comment + optional photos,
/// attached either to an existing [Place] or to a custom place the user just
/// created on the spot.
class Contribution {
  final String id;
  final String? placeId; // null when this is a brand-new custom place
  final String placeName;
  final String categoryName;
  final double latitude;
  final double longitude;
  final double rating; // 0.0 – 5.0
  final String comment;
  final List<String> photos; // local file paths or remote URLs
  final bool isCustomPlace;
  final DateTime createdAt;
  final String? ratingId; // server-assigned _id of the place_ratings document

  const Contribution({
    required this.id,
    required this.placeName,
    required this.categoryName,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.comment,
    required this.photos,
    required this.isCustomPlace,
    required this.createdAt,
    this.placeId,
    this.ratingId,
  });

  Contribution copyWith({
    String? placeName,
    String? categoryName,
    double? latitude,
    double? longitude,
    double? rating,
    String? comment,
    List<String>? photos,
    bool? isCustomPlace,
    String? placeId,
    String? ratingId,
  }) {
    return Contribution(
      id: id,
      placeName: placeName ?? this.placeName,
      categoryName: categoryName ?? this.categoryName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      photos: photos ?? this.photos,
      isCustomPlace: isCustomPlace ?? this.isCustomPlace,
      placeId: placeId ?? this.placeId,
      ratingId: ratingId ?? this.ratingId,
      createdAt: createdAt,
    );
  }

  factory Contribution.forPlace({
    required String id,
    required Place place,
    required double rating,
    required String comment,
    required List<String> photos,
    DateTime? createdAt,
  }) {
    return Contribution(
      id: id,
      placeId: place.id,
      placeName: place.name,
      categoryName: place.category?.name ?? 'Place',
      latitude: place.latitude,
      longitude: place.longitude,
      rating: rating,
      comment: comment,
      photos: photos,
      isCustomPlace: false,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'placeId': placeId,
        'ratingId': ratingId,
        'placeName': placeName,
        'categoryName': categoryName,
        'latitude': latitude,
        'longitude': longitude,
        'rating': rating,
        'comment': comment,
        'photos': photos,
        'isCustomPlace': isCustomPlace,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Contribution.fromJson(Map<String, dynamic> json) {
    return Contribution(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      placeId: json['placeId'] as String?,
      ratingId: json['ratingId'] as String?,
      placeName: json['placeName'] as String? ?? '',
      categoryName: json['categoryName'] as String? ?? 'Place',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      comment: json['comment'] as String? ?? '',
      photos: (json['photos'] as List?)?.whereType<String>().toList() ??
          const <String>[],
      isCustomPlace: json['isCustomPlace'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

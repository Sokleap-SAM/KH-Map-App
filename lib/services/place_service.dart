import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/place.dart';
import '../models/place_category.dart';
import '../models/place_rating.dart';

class PlaceService {
  static String get _baseUrl =>
      dotenv.env['BASE_URL'] ?? 'http://10.0.2.2:3000';

  Future<List<Place>> fetchPlaces() async {
    final uri = Uri.parse('$_baseUrl/places');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to load places');
    final List data = jsonDecode(response.body) as List;
    return data.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<PlaceCategory>> fetchCategories() async {
    final uri = Uri.parse('$_baseUrl/places/categories');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load categories');
    }
    final List data = jsonDecode(response.body) as List;
    return data
        .map((e) => PlaceCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submits a brand-new place as a PENDING request (POST /places/requests).
  /// The place is NOT published to the map until an admin approves it. Photos
  /// are uploaded as multipart files and stored on Cloudinary by the backend.
  /// Requires a logged-in user — the backend derives the submitter from the JWT.
  /// Returns the created [Place] (with its server id, remote photo URLs and
  /// status: pending).
  Future<Place> submitPlaceRequest({
    required String nameInKhmer,
    required String nameInLatin,
    String? categoryId,
    required double longitude,
    required double latitude,
    List<String> photoPaths = const [],
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places/requests');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    // The deployed backend stores the place label in a single required `name`
    // field and drops unknown fields (`nameInKhmer`/`nameInLatin`). We send all
    // three so this works whether the server is the `name` build (uses `name`)
    // or the newer `nameInKhmer` build (uses those + ignores `name`). Without
    // `name`, the `name` build rejects the create as an empty required field.
    request.fields['name'] = nameInKhmer;
    request.fields['nameInKhmer'] = nameInKhmer;
    request.fields['nameInLatin'] = nameInLatin;
    if (categoryId != null && categoryId.isNotEmpty) {
      request.fields['category'] = categoryId;
    }
    // Backend expects [longitude, latitude] (GeoJSON order).
    request.fields['location'] = jsonEncode([longitude, latitude]);
    for (final path in photoPaths) {
      request.files.add(await http.MultipartFile.fromPath('photos', path));
    }

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to submit place request: ${response.statusCode} ${response.body}',
      );
    }
    return Place.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Edits an existing place the user created (PATCH /places/:id) instead of
  /// POSTing a new request, so an edit updates the same document rather than
  /// creating a duplicate. Sends the same multipart fields as
  /// [submitPlaceRequest]. Photos are only touched when [photoPaths] is
  /// non-empty — the backend then replaces the place's photos with the newly
  /// uploaded files; passing none leaves the existing photos untouched.
  /// Returns the updated [Place].
  Future<Place> updatePlaceRequest({
    required String placeId,
    required String nameInKhmer,
    required String nameInLatin,
    String? categoryId,
    required double longitude,
    required double latitude,
    List<String> photoPaths = const [],
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId');
    final request = http.MultipartRequest('PATCH', uri);
    request.headers['Authorization'] = 'Bearer $token';
    // Send `name` too — the deployed `name` build only updates that field and
    // ignores `nameInKhmer`, so a name-edit is a no-op without it. See
    // [submitPlaceRequest] for the full rationale.
    request.fields['name'] = nameInKhmer;
    request.fields['nameInKhmer'] = nameInKhmer;
    request.fields['nameInLatin'] = nameInLatin;
    if (categoryId != null && categoryId.isNotEmpty) {
      request.fields['category'] = categoryId;
    }
    // Backend expects [longitude, latitude] (GeoJSON order).
    request.fields['location'] = jsonEncode([longitude, latitude]);
    for (final path in photoPaths) {
      request.files.add(await http.MultipartFile.fromPath('photos', path));
    }

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to update place: ${response.statusCode} ${response.body}',
      );
    }
    return Place.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Edits an existing rating (PATCH /places/:placeId/ratings/:ratingId) —
  /// updates the score/comment and recomputes the place's average. Existing
  /// photos on the rating are preserved (this endpoint doesn't re-upload
  /// files). Returns the updated rating document as JSON.
  Future<Map<String, dynamic>> updateRating({
    required String placeId,
    required String ratingId,
    required int score,
    String? comment,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId/ratings/$ratingId');
    final response = await http
        .patch(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'score': score,
            'comment':
                (comment != null && comment.trim().isNotEmpty)
                ? comment.trim()
                : null,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to update rating: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Fetches the current user's own place requests (all statuses), newest
  /// first. Used by the contribution screen to show whether each submission is
  /// still pending or has been approved / rejected.
  Future<List<Place>> fetchMyPlaceRequests(String token) async {
    final uri = Uri.parse('$_baseUrl/places/requests/mine');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load place requests');
    }
    final List data = jsonDecode(response.body) as List;
    return data.map((e) => Place.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetches every rating the current user has left (newest first), as raw
  /// JSON maps. Each entry carries the populated `placeId` place object so the
  /// contributions list can be rebuilt from the database after local storage
  /// is lost (reinstall, cleared app data, new device).
  Future<List<Map<String, dynamic>>> fetchMyRatings(String token) async {
    final uri = Uri.parse('$_baseUrl/places/ratings/mine');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load my ratings');
    }
    final List data = jsonDecode(response.body) as List;
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// Fetches every review for a place (newest first), each carrying the
  /// reviewer's name, score, optional comment and attached photos.
  Future<List<PlaceRating>> fetchRatings(String placeId) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId/ratings');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to load ratings');
    }
    final List data = jsonDecode(response.body) as List;
    return data
        .map((e) => PlaceRating.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Submits a rating (score + optional comment + optional photos) for an
  /// existing place. Stored in the `place_ratings` collection. Requires a
  /// logged-in user — the backend derives the author from the JWT.
  /// Returns the created rating document as JSON.
  Future<Map<String, dynamic>> submitRating({
    required String placeId,
    required int score,
    String? comment,
    List<String> photoPaths = const [],
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId/ratings');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['score'] = score.toString();
    if (comment != null && comment.trim().isNotEmpty) {
      request.fields['comment'] = comment.trim();
    }
    for (final path in photoPaths) {
      request.files.add(await http.MultipartFile.fromPath('photos', path));
    }

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Failed to submit rating: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteRating({
    required String placeId,
    required String ratingId,
    required String token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places/$placeId/ratings/$ratingId');
    final response = await http
        .delete(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
        'Failed to delete rating: ${response.statusCode} ${response.body}',
      );
    }
  }
}

import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/place.dart';
import '../models/place_category.dart';

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

  /// Creates a brand-new place in the `places` collection. Photos are uploaded
  /// as multipart files and stored on Cloudinary by the backend. Returns the
  /// created [Place] (with its server id and remote photo URLs).
  Future<Place> createPlace({
    required String name,
    String? categoryId,
    required double longitude,
    required double latitude,
    List<String> photoPaths = const [],
    String? token,
  }) async {
    final uri = Uri.parse('$_baseUrl/places');
    final request = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    request.fields['name'] = name;
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
        'Failed to create place: ${response.statusCode} ${response.body}',
      );
    }
    return Place.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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

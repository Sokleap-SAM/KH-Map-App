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
}

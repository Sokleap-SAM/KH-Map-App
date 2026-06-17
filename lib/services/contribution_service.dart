import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contribution.dart';
import 'place_service.dart';

/// Local-first store for [Contribution]s. Persists to SharedPreferences,
/// scoped per logged-in user (falls back to a "guest" bucket).
///
/// Photos selected via image_picker live in the app's temp cache, which the
/// OS may purge. To make them survive a relaunch we copy each picked file
/// into the documents directory via [persistPhoto] before saving.
class ContributionService {
  static const String _keyPrefix = 'contributions_';
  static const String _guestSuffix = 'guest';
  static const String _tokenKey = 'access_token';
  static const String _photoDir = 'contribution_photos';

  final PlaceService _placeService = PlaceService();

  Future<String?> _accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<String> _userKey() async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    return '$_keyPrefix${userId ?? _guestSuffix}';
  }

  static String? _extractUserId(String? token) {
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1];
      final pad = payload.length % 4;
      if (pad != 0) payload = payload + '=' * (4 - pad);
      final jsonString = utf8.decode(base64Url.decode(payload));
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final raw = data['sub'] ?? data['_id'] ?? data['id'] ?? data['email'];
      return raw?.toString();
    } catch (_) {
      return null;
    }
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  Future<List<Contribution>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Contribution>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Contribution.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Contribution>[];
    }
  }

  /// Saves a new contribution. Best-effort: pushes it to the backend database
  /// first — a custom place goes to the `places` collection, a rating of an
  /// existing place goes to `place_ratings` (score, comment, photos). The
  /// returned/synced version (with remote photo URLs and server placeId) is
  /// then cached locally so it shows in the "My Contributions" list. If the
  /// backend is unreachable or the user is a guest, it falls back to local-only.
  Future<List<Contribution>> add(Contribution contribution) async {
    final synced = await _syncToBackend(contribution);
    return _localAdd(synced ?? contribution);
  }

  /// Edits are kept local-only so we don't create duplicate database rows.
  Future<List<Contribution>> update(Contribution contribution) =>
      _localAdd(contribution);

  Future<List<Contribution>> _localAdd(Contribution contribution) async {
    final entries = await load();
    entries.removeWhere((c) => c.id == contribution.id);
    entries.insert(0, contribution);
    await _persist(entries);
    return entries;
  }

  // ─── Backend sync ────────────────────────────────────────────────────────

  /// Pushes [c] to the backend. Returns a copy updated with the server-assigned
  /// placeId and remote (Cloudinary) photo URLs on success, or null on failure
  /// / when the contribution can't be synced (guest rating, etc.).
  Future<Contribution?> _syncToBackend(Contribution c) async {
    final localPhotos = c.photos.where((p) => !_isRemote(p)).toList();
    try {
      if (c.isCustomPlace) {
        final token = await _accessToken();
        final categoryId = await _resolveCategoryId(c.categoryName);
        final place = await _placeService.createPlace(
          name: c.placeName,
          categoryId: categoryId,
          longitude: c.longitude,
          latitude: c.latitude,
          photoPaths: localPhotos,
          token: token,
        );
        final photos = _mergeRemotePhotos(c.photos, place.photos);
        await _cleanupPhotos(localPhotos);
        return c.copyWith(placeId: place.id, photos: photos);
      }

      // Rating an existing place — needs a logged-in user and a real placeId.
      final token = await _accessToken();
      if (token == null || c.placeId == null || c.placeId!.isEmpty) {
        debugPrint('[Contributions] rating not synced (guest or no placeId)');
        return null;
      }
      final rating = await _placeService.submitRating(
        placeId: c.placeId!,
        score: c.rating.round().clamp(1, 5),
        comment: c.comment,
        photoPaths: localPhotos,
        token: token,
      );
      final remotePhotos =
          (rating['photos'] as List?)?.whereType<String>().toList() ??
              const <String>[];
      final photos = _mergeRemotePhotos(c.photos, remotePhotos);
      final ratingId =
          (rating['_id'] ?? rating['id'])?.toString();
      await _cleanupPhotos(localPhotos);
      return c.copyWith(photos: photos, ratingId: ratingId);
    } catch (e) {
      debugPrint('[Contributions] backend sync failed: $e — keeping local copy');
      return null;
    }
  }

  /// Finds the category id matching [name] (case-insensitive). Returns null
  /// when there's no DB category by that name, so the place is created without.
  Future<String?> _resolveCategoryId(String name) async {
    try {
      final cats = await _placeService.fetchCategories();
      for (final c in cats) {
        if (c.name.toLowerCase() == name.toLowerCase()) return c.id;
      }
    } catch (_) {/* category lookup is best-effort */}
    return null;
  }

  /// Keeps any already-remote URLs from the original list and appends the
  /// newly-uploaded remote URLs returned by the backend.
  List<String> _mergeRemotePhotos(
    List<String> original,
    List<String> uploaded,
  ) {
    return [...original.where(_isRemote), ...uploaded];
  }

  bool _isRemote(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  Future<List<Contribution>> remove(String id) async {
    final entries = await load();
    final removed = <Contribution>[];
    entries.removeWhere((c) {
      if (c.id == id) {
        removed.add(c);
        return true;
      }
      return false;
    });
    await _persist(entries);
    for (final c in removed) {
      await _cleanupPhotos(c.photos);
      if (!c.isCustomPlace &&
          c.placeId != null &&
          c.placeId!.isNotEmpty &&
          c.ratingId != null &&
          c.ratingId!.isNotEmpty) {
        try {
          final token = await _accessToken();
          if (token != null) {
            await _placeService.deleteRating(
              placeId: c.placeId!,
              ratingId: c.ratingId!,
              token: token,
            );
          }
        } catch (e) {
          debugPrint('[Contributions] backend delete failed: $e');
        }
      }
    }
    return entries;
  }

  Future<void> clear() async {
    final all = await load();
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.remove(key);
    for (final c in all) {
      await _cleanupPhotos(c.photos);
    }
  }

  // ─── Photo helpers ─────────────────────────────────────────────────────────

  /// Copies a freshly-picked photo into the app's documents directory so it
  /// survives app relaunches. Returns the absolute path to the stored copy.
  /// Remote URLs (http/https) are passed through unchanged.
  Future<String> persistPhoto(String sourcePath) async {
    if (sourcePath.startsWith('http://') ||
        sourcePath.startsWith('https://')) {
      return sourcePath;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/$_photoDir');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = _extensionOf(sourcePath);
      final filename =
          '${DateTime.now().microsecondsSinceEpoch}_${sourcePath.hashCode.abs()}$ext';
      final target = File('${dir.path}/$filename');
      await File(sourcePath).copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('[Contributions] persistPhoto failed: $e — keeping original');
      return sourcePath;
    }
  }

  Future<void> _cleanupPhotos(List<String> paths) async {
    for (final p in paths) {
      if (p.startsWith('http://') || p.startsWith('https://')) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {/* ignore */}
    }
  }

  String _extensionOf(String path) {
    final i = path.lastIndexOf('.');
    if (i == -1 || i == path.length - 1) return '.jpg';
    final ext = path.substring(i).toLowerCase();
    if (ext.length > 5) return '.jpg';
    return ext;
  }

  Future<void> _persist(List<Contribution> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _userKey();
    await prefs.setString(
      key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

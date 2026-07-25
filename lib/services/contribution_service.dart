import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contribution.dart';
import '../models/place.dart';
import '../models/place_rating.dart';
import 'place_service.dart';

/// Result of [ContributionService.syncWithBackend]: the merged contributions
/// list plus the raw server-side place requests (which carry the
/// pending/approved/rejected status for the badges and the bell).
class ContributionSyncResult {
  final List<Contribution> contributions;
  final List<Place> requests;

  const ContributionSyncResult({
    required this.contributions,
    required this.requests,
  });
}

/// Local-first store for [Contribution]s. Persists to SharedPreferences,
/// scoped per logged-in user (falls back to a "guest" bucket), and merges the
/// user's server-side contributions back in via [syncWithBackend] — matched by
/// their account id — so the list survives lost local storage (reinstall,
/// cleared app data, new device).
///
/// Photos selected via image_picker live in the app's temp cache, which the
/// OS may purge. To make them survive a relaunch we copy each picked file
/// into the documents directory via [persistPhoto] before saving.
class ContributionService {
  static const String _keyPrefix = 'contributions_';
  static const String _seenPrefix = 'seen_place_requests_';
  static const String _removedPrefix = 'removed_sync_ids_';
  static const String _guestSuffix = 'guest';
  static const String _tokenKey = 'access_token';
  static const String _photoDir = 'contribution_photos';

  final PlaceService _placeService = PlaceService();

  /// Serializes every local read-modify-write. Without this, two overlapping
  /// saves both `load()` the same snapshot and the last `_persist` silently
  /// drops the other's entry (easy to hit: `add` uploads photos to the backend
  /// first, which takes seconds, and the form sheet can be dismissed while the
  /// save is still running). Static so every service instance shares one queue.
  static Future<void> _writeQueue = Future.value();

  static Future<T> _locked<T>(Future<T> Function() action) {
    final run = _writeQueue.then((_) => action());
    _writeQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

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

  /// Saves an edit to an existing contribution. Pushes the change to the
  /// backend so it's reflected everywhere the data is read from the database
  /// (place reviews, the map's average rating, the place itself) — not just in
  /// this device's local cache — then updates the local copy. Unlike [add],
  /// this targets the existing document (PATCH) so an edit never creates a
  /// duplicate. Falls back to a local-only save if the backend is unreachable
  /// or the entry was never synced (guest / offline original).
  Future<List<Contribution>> update(Contribution contribution) async {
    final synced = await _syncEditToBackend(contribution);
    return _localAdd(synced ?? contribution);
  }

  /// Pushes an edited contribution to the backend via the update (PATCH)
  /// endpoints. Returns a copy reconciled with the server response, or null
  /// when the edit can't be synced (guest, no server id yet, or a network
  /// error) so the caller can fall back to a local-only save.
  Future<Contribution?> _syncEditToBackend(Contribution c) async {
    final token = await _accessToken();
    if (token == null) return null;
    final localPhotos = c.photos.where((p) => !_isRemote(p)).toList();
    try {
      if (c.isCustomPlace) {
        // A place that was never synced (no server id) has nothing to PATCH —
        // treat the edit as a first-time create so it still reaches the DB.
        if (c.placeId == null || c.placeId!.isEmpty) {
          return _syncToBackend(c);
        }
        final categoryId = await _resolveCategoryId(c.categoryName);
        final place = await _placeService.updatePlaceRequest(
          placeId: c.placeId!,
          nameInKhmer: c.placeNameKhmer,
          nameInLatin: c.placeNameLatin,
          categoryId: categoryId,
          longitude: c.longitude,
          latitude: c.latitude,
          photoPaths: localPhotos,
          token: token,
        );
        // When new photos were uploaded the backend replaced the place's photo
        // set, so mirror exactly what it stored; otherwise keep what we have.
        final photos = localPhotos.isEmpty ? c.photos : place.photos;
        if (localPhotos.isNotEmpty) await _cleanupPhotos(localPhotos);
        return c.copyWith(placeId: place.id, photos: photos);
      }

      // Rating edit. Needs the server ids; without a ratingId there's no row to
      // PATCH, so fall back to the create/upsert path (which also handles a
      // rating that was first saved offline).
      if (c.placeId == null || c.placeId!.isEmpty) return null;
      if (c.ratingId == null || c.ratingId!.isEmpty) {
        return _syncToBackend(c);
      }
      await _placeService.updateRating(
        placeId: c.placeId!,
        ratingId: c.ratingId!,
        score: c.rating.round().clamp(1, 5),
        comment: c.comment,
        token: token,
      );
      return c;
    } catch (_) {
      return null;
    }
  }

  /// Merges the user's server-side contributions — place requests they created
  /// (matched by `createdBy`) and ratings they left (matched by `userId`) —
  /// into the local list, so "My Contributions" can be rebuilt from the
  /// database after local storage is lost. Local entries stay the source of
  /// truth for anything they already cover: server entries are only *added*
  /// when missing, never overwrite local edits. Entries the user deleted
  /// locally are tombstoned (see [_removedSyncIds]) and stay hidden. The
  /// merged list is persisted so it's available offline next launch.
  ///
  /// Guests (or full fetch failure) just get the local list back, with each
  /// fetch failing independently — if only the ratings call fails, place
  /// requests still merge.
  Future<ContributionSyncResult> syncWithBackend() async {
    final token = await _accessToken();
    if (token == null) {
      return ContributionSyncResult(
        contributions: await load(),
        requests: const [],
      );
    }

    List<Place> requests = const [];
    try {
      requests = await _placeService.fetchMyPlaceRequests(token);
    } catch (_) {
      /* offline / backend down — merge whatever we do have */
    }
    List<Map<String, dynamic>> ratings = const [];
    try {
      ratings = await _placeService.fetchMyRatings(token);
    } catch (_) {
      /* endpoint unavailable — place requests still merge */
    }

    final contributions = await _locked(() async {
      final entries = await load();
      final removed = await _removedSyncIds();

      final knownPlaceIds = {
        for (final c in entries)
          if (c.isCustomPlace && c.placeId != null) c.placeId!,
      };
      final knownRatingIds = {
        for (final c in entries)
          if (c.ratingId != null) c.ratingId!,
      };
      // Rated places whose local entry predates ratingId tracking — matched by
      // placeId so restoring from the server doesn't duplicate them.
      final ratedPlaceIds = {
        for (final c in entries)
          if (!c.isCustomPlace && c.placeId != null) c.placeId!,
      };

      var changed = false;
      for (final place in requests) {
        if (removed.contains(place.id) || knownPlaceIds.contains(place.id)) {
          continue;
        }
        entries.add(_contributionFromPlace(place));
        changed = true;
      }
      for (final raw in ratings) {
        final rating = PlaceRating.fromJson(raw);
        if (rating.id.isEmpty ||
            removed.contains(rating.id) ||
            knownRatingIds.contains(rating.id)) {
          continue;
        }
        final placeJson = raw['placeId'];
        if (placeJson is! Map<String, dynamic>) continue; // place deleted
        final Place place;
        try {
          place = Place.fromJson(placeJson);
        } catch (_) {
          continue; // malformed populate — skip rather than fail the sync
        }
        if (ratedPlaceIds.contains(place.id)) continue;
        entries.add(_contributionFromRating(rating, place));
        changed = true;
      }

      if (changed) {
        entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        await _persist(entries);
      }
      return entries;
    });

    return ContributionSyncResult(
      contributions: contributions,
      requests: requests,
    );
  }

  /// A place request restored from the server. The rating/comment the user
  /// typed alongside the original submission never left the device (only the
  /// place itself is uploaded), so those come back empty.
  Contribution _contributionFromPlace(Place place) {
    return Contribution(
      id: place.id, // server id — stable, so repeated merges can't duplicate
      placeId: place.id,
      placeNameKhmer: place.nameInKhmer,
      placeNameLatin: place.nameInLatin,
      categoryName: place.category?.name ?? 'Place',
      latitude: place.latitude,
      longitude: place.longitude,
      rating: 0,
      comment: '',
      photos: place.photos,
      isCustomPlace: true,
      createdAt: place.createdAt ?? DateTime.now(),
    );
  }

  /// A rating of an existing place restored from the server, with the place
  /// details taken from the populated `placeId` document.
  Contribution _contributionFromRating(PlaceRating rating, Place place) {
    return Contribution(
      id: rating.id,
      placeId: place.id,
      ratingId: rating.id,
      placeNameKhmer: place.nameInKhmer,
      placeNameLatin: place.nameInLatin,
      categoryName: place.category?.name ?? 'Place',
      latitude: place.latitude,
      longitude: place.longitude,
      rating: rating.score,
      comment: rating.comment ?? '',
      photos: rating.photos,
      isCustomPlace: false,
      createdAt: rating.createdAt ?? DateTime.now(),
    );
  }

  // ─── Request notifications (seen / unseen tracking) ────────────────────────

  Future<String> _seenKey() async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    return '$_seenPrefix${userId ?? _guestSuffix}';
  }

  /// Ids of resolved requests the user has already viewed in the notifications
  /// sheet — used to decide which approvals/rejections still count as "new".
  Future<Set<String>> acknowledgedRequestIds() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _seenKey();
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  /// Marks the given request ids as seen so they stop showing on the badge.
  Future<void> acknowledgeRequests(Iterable<String> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = await _seenKey();
    final current = (prefs.getStringList(key) ?? const <String>[]).toSet()
      ..addAll(list);
    await prefs.setStringList(key, current.toList());
  }

  // ─── Removed-entry tombstones ──────────────────────────────────────────────
  // Server ids (placeId of a created place / ratingId of a rating) the user
  // deleted locally. [syncWithBackend] skips these so a locally-deleted entry
  // doesn't get restored from the database on the next sync.

  Future<String> _removedKey() async {
    final token = await _accessToken();
    final userId = _extractUserId(token);
    return '$_removedPrefix${userId ?? _guestSuffix}';
  }

  Future<Set<String>> _removedSyncIds() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _removedKey();
    return (prefs.getStringList(key) ?? const <String>[]).toSet();
  }

  Future<void> _markRemoved(Iterable<String?> ids) async {
    final list = ids.whereType<String>().where((id) => id.isNotEmpty).toList();
    if (list.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = await _removedKey();
    final current = (prefs.getStringList(key) ?? const <String>[]).toSet()
      ..addAll(list);
    await prefs.setStringList(key, current.toList());
  }

  Future<List<Contribution>> _localAdd(Contribution contribution) {
    return _locked(() async {
      final entries = await load();
      entries.removeWhere(
        (c) =>
            c.id == contribution.id ||
            // The backend keeps one rating per user per place (upsert on
            // re-submit), so a new rating of the same place replaces the older
            // local entry instead of duplicating it.
            (!contribution.isCustomPlace &&
                !c.isCustomPlace &&
                contribution.placeId != null &&
                c.placeId == contribution.placeId),
      );
      entries.insert(0, contribution);
      await _persist(entries);
      return entries;
    });
  }

  // ─── Backend sync ────────────────────────────────────────────────────────

  /// Pushes [c] to the backend. Returns a copy updated with the server-assigned
  /// placeId and remote (Cloudinary) photo URLs on success, or null on failure
  /// / when the contribution can't be synced (guest rating, etc.).
  Future<Contribution?> _syncToBackend(Contribution c) async {
    final localPhotos = c.photos.where((p) => !_isRemote(p)).toList();
    try {
      if (c.isCustomPlace) {
        // A new place is a request that needs admin approval — it requires a
        // logged-in user (the backend ties the request to the JWT). Guests
        // fall back to a local-only entry.
        final token = await _accessToken();
        if (token == null) {
          return null;
        }
        final categoryId = await _resolveCategoryId(c.categoryName);
        final place = await _placeService.submitPlaceRequest(
          nameInKhmer: c.placeNameKhmer,
          nameInLatin: c.placeNameLatin,
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
      final ratingId = (rating['_id'] ?? rating['id'])?.toString();
      await _cleanupPhotos(localPhotos);
      return c.copyWith(photos: photos, ratingId: ratingId);
    } catch (e) {
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
    } catch (_) {
      /* category lookup is best-effort */
    }
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
    final removed = <Contribution>[];
    // Local removal + tombstoning run under the write lock; the slow
    // best-effort backend cleanup below stays outside so it can't stall other
    // saves queued behind it.
    final entries = await _locked(() async {
      final list = await load();
      list.removeWhere((c) {
        if (c.id == id) {
          removed.add(c);
          return true;
        }
        return false;
      });
      await _persist(list);
      await _markRemoved([
        for (final c in removed) c.isCustomPlace ? c.placeId : c.ratingId,
      ]);
      return list;
    });
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
        } catch (_) {
          // backend delete is best-effort; local removal still applies. If it
          // failed, the tombstone above keeps the entry hidden regardless.
        }
      }
    }
    return entries;
  }

  Future<void> clear() async {
    final all = await _locked(() async {
      final list = await load();
      final prefs = await SharedPreferences.getInstance();
      final key = await _userKey();
      await prefs.remove(key);
      await _markRemoved([
        for (final c in list) c.isCustomPlace ? c.placeId : c.ratingId,
      ]);
      return list;
    });
    for (final c in all) {
      await _cleanupPhotos(c.photos);
    }
  }

  // ─── Photo helpers ─────────────────────────────────────────────────────────

  /// Copies a freshly-picked photo into the app's documents directory so it
  /// survives app relaunches. Returns the absolute path to the stored copy.
  /// Remote URLs (http/https) are passed through unchanged.
  Future<String> persistPhoto(String sourcePath) async {
    if (sourcePath.startsWith('http://') || sourcePath.startsWith('https://')) {
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
      return sourcePath;
    }
  }

  Future<void> _cleanupPhotos(List<String> paths) async {
    for (final p in paths) {
      if (p.startsWith('http://') || p.startsWith('https://')) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {
        /* ignore */
      }
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

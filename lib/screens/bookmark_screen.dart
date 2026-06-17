import 'package:flutter/material.dart';

import '../models/favorite_route.dart';
import '../models/route_search_selection.dart';
import '../providers/map_provider.dart';
import '../services/auth_service.dart';
import '../services/favorite_routes_service.dart';
import '../services/favorites_service.dart';
import '../utils/constants/colors.dart';
import '../widgets/bookmark_screen/favorite_place_card.dart';
import '../widgets/bookmark_screen/favorite_place_sheet.dart';
import '../widgets/bookmark_screen/favorite_route_card.dart';
import '../widgets/bookmark_screen/favorite_route_sheet.dart';

/// "Saved places" screen — the user's favourite places, presented in the
/// style of the Google Maps *Saved* tab: a list-header banner, category
/// filter chips, sortable cards, swipe-to-remove and a detail sheet.
class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key, this.onNavigateToMap});

  /// Switches the app to the map tab — used when opening a saved route so the
  /// overlay, route card and drawn polyline appear on the map.
  final VoidCallback? onNavigateToMap;

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

/// Which list the bookmark screen is currently showing.
enum _BookmarkTab { places, routes }

class _BookmarkScreenState extends State<BookmarkScreen> {
  final FavoritesService _service = FavoritesService();
  final FavoriteRoutesService _routesService = FavoriteRoutesService();
  final Distance _distance = const Distance();

  _BookmarkTab _tab = _BookmarkTab.places;

  List<FavoritePlace> _favorites = [];
  bool _loading = true;
  String? _error;

  // Favorite routes.
  List<FavoriteRoute> _routes = [];
  bool _routesLoading = true;
  String? _routesError;

  // Filter + sort state.
  String? _categoryFilter; // null = show every category
  String _sort = 'recent'; // recent | name | rating | distance

  @override
  void initState() {
    super.initState();
    _load();
    _loadRoutes();
    // Keep the list in sync when the user logs in / out elsewhere.
    AuthService.tokenNotifier.addListener(_onAuthChanged);
    // This screen lives in an IndexedStack (always alive), so reload whenever a
    // route is saved/removed on another tab instead of waiting for a restart.
    FavoriteRoutesService.changes.addListener(_onRoutesChanged);
  }

  @override
  void dispose() {
    AuthService.tokenNotifier.removeListener(_onAuthChanged);
    FavoriteRoutesService.changes.removeListener(_onRoutesChanged);
    super.dispose();
  }

  void _onRoutesChanged() {
    if (!mounted) return;
    _loadRoutes();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {
      _favorites = [];
      _loading = true;
      _routes = [];
      _routesLoading = true;
    });
    _load();
    _loadRoutes();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final favorites = await _service.load();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'មិនអាចទាញយកទីកន្លែងដែលបានរក្សាទុកបានទេ';
        _loading = false;
      });
    }
  }

  Future<void> _loadRoutes() async {
    setState(() => _routesError = null);
    try {
      final routes = await _routesService.load();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _routesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routesError = 'មិនអាចទាញយកផ្លូវដែលបានរក្សាទុកបានទេ';
        _routesLoading = false;
      });
    }
  }

  // ---------- Derived data ----------

  double _metersFrom(FavoritePlace f, LatLng user) =>
      _distance.as(LengthUnit.Meter, user, LatLng(f.latitude, f.longitude));

  String? _distanceLabel(FavoritePlace f, LatLng? user) {
    if (user == null) return null;
    final meters = _metersFrom(f, user);
    if (meters < 950) return '${meters.round()} ម';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} គម';
  }

  List<String> get _categories {
    final seen = <String>{};
    for (final f in _favorites) {
      if (f.categoryName.trim().isNotEmpty) seen.add(f.categoryName);
    }
    final list = seen.toList()..sort();
    return list;
  }

  List<FavoritePlace> _visibleFavorites(LatLng? user) {
    final list = _favorites
        .where(
          (f) => _categoryFilter == null || f.categoryName == _categoryFilter,
        )
        .toList();
    switch (_sort) {
      case 'name':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'rating':
        list.sort(
          (a, b) => (b.averageRating ?? -1).compareTo(a.averageRating ?? -1),
        );
        break;
      case 'distance':
        if (user != null) {
          list.sort(
            (a, b) => _metersFrom(a, user).compareTo(_metersFrom(b, user)),
          );
        }
        break;
      default: // recent
        list.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    }
    return list;
  }

  // ---------- Actions ----------

  void _copyCoordinates(FavoritePlace f) {
    final text = '${f.latitude}, ${f.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    _snack('បានចម្លងទីតាំង៖ $text');
  }

  void _removeFavorite(FavoritePlace f) {
    final index = _favorites.indexWhere((e) => e.placeId == f.placeId);
    if (index < 0) return;
    setState(() => _favorites.removeAt(index));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              'បានលុប «${f.name}» ចេញពីចំណាំ',
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'មិនធ្វើវិញ',
              textColor: AppColors.secondaryColor,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _favorites.insert(index.clamp(0, _favorites.length), f);
                });
              },
            ),
          ),
        )
        .closed
        .then((reason) {
          // Commit the deletion only if the user did not tap "undo".
          if (reason != SnackBarClosedReason.action) {
            _service.remove(f.placeId);
          }
        });
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF243456),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'លុបចំណាំទាំងអស់?',
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'ទីកន្លែងដែលបានរក្សាទុកទាំង ${_favorites.length} នឹងត្រូវបានយកចេញ។',
          style: GoogleFonts.notoSansKhmer(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'បោះបង់',
              style: GoogleFonts.notoSansKhmer(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'លុបទាំងអស់',
              style: GoogleFonts.notoSansKhmer(
                color: AppColors.alertBorderColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.clear();
    if (!mounted) return;
    setState(() => _favorites = []);
    _snack('បានលុបចំណាំទាំងអស់');
  }

  void _openDetail(FavoritePlace f, String? distanceLabel) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FavoritePlaceSheet(favorite: f, distanceLabel: distanceLabel),
    );
    if (result == kFavSheetRemove) _removeFavorite(f);
  }

  // ---------- Favorite routes ----------

  void _removeRoute(FavoriteRoute r) {
    final index = _routes.indexWhere((e) => e.id == r.id);
    if (index < 0) return;
    setState(() => _routes.removeAt(index));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              'បានលុបផ្លូវចេញពីចំណាំ',
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'មិនធ្វើវិញ',
              textColor: AppColors.secondaryColor,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _routes.insert(index.clamp(0, _routes.length), r);
                });
              },
            ),
          ),
        )
        .closed
        .then((reason) {
          if (reason != SnackBarClosedReason.action) {
            _routesService.remove(r.id);
          }
        });
  }

  void _openRouteDetail(FavoriteRoute r) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FavoriteRouteSheet(favorite: r),
    );
    if (result == kFavRouteSheetRemove) _removeRoute(r);
    if (result == kFavRouteSheetGo) _goToRoute(r);
  }

  /// Opens the saved route on the map: feeds its fixed origin/destination into
  /// the routing flow (overlay + route info card + drawn polyline, re-planned
  /// from the saved endpoints) then switches to the map tab.
  void _goToRoute(FavoriteRoute r) {
    context.read<MapProvider>().openFavoriteRoute(
      favoriteId: r.id,
      origin: RouteSearchSelection(
        label: r.origin.name.isEmpty ? 'ដើម' : r.origin.name,
        location: r.origin.coordinates,
      ),
      destination: RouteSearchSelection(
        label: r.destination.name.isEmpty ? 'គោលដៅ' : r.destination.name,
        location: r.destination.coordinates,
      ),
    );
    widget.onNavigateToMap?.call();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(message, style: GoogleFonts.notoSansKhmer(fontSize: 13)),
      ),
    );
  }

  // ---------- Build ----------

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final FavoritesService _service = FavoritesService();
  final Distance _distance = const Distance();

  List<FavoritePlace> _favorites = [];
  bool _loading = true;
  String? _error;

  // Filter + sort state.
  String? _categoryFilter; // null = show every category
  String _sort = 'recent'; // recent | name | rating | distance

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the list in sync when the user logs in / out elsewhere.
    AuthService.tokenNotifier.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService.tokenNotifier.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {
      _favorites = [];
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final favorites = await _service.load();
      if (!mounted) return;
      setState(() {
        _favorites = favorites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'មិនអាចទាញយកទីកន្លែងដែលបានរក្សាទុកបានទេ';
        _loading = false;
      });
    }
  }

  // ---------- Derived data ----------

  double _metersFrom(FavoritePlace f, LatLng user) =>
      _distance.as(LengthUnit.Meter, user, LatLng(f.latitude, f.longitude));

  String? _distanceLabel(FavoritePlace f, LatLng? user) {
    if (user == null) return null;
    final meters = _metersFrom(f, user);
    if (meters < 950) return '${meters.round()} ម';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} គម';
  }

  List<String> get _categories {
    final seen = <String>{};
    for (final f in _favorites) {
      if (f.categoryName.trim().isNotEmpty) seen.add(f.categoryName);
    }
    final list = seen.toList()..sort();
    return list;
  }

  List<FavoritePlace> _visibleFavorites(LatLng? user) {
    final list = _favorites
        .where((f) => _categoryFilter == null || f.categoryName == _categoryFilter)
        .toList();
    switch (_sort) {
      case 'name':
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case 'rating':
        list.sort(
          (a, b) => (b.averageRating ?? -1).compareTo(a.averageRating ?? -1),
        );
        break;
      case 'distance':
        if (user != null) {
          list.sort(
            (a, b) => _metersFrom(a, user).compareTo(_metersFrom(b, user)),
          );
        }
        break;
      default: // recent
        list.sort((a, b) => b.favoritedAt.compareTo(a.favoritedAt));
    }
    return list;
  }

  // ---------- Actions ----------

  void _copyCoordinates(FavoritePlace f) {
    final text = '${f.latitude}, ${f.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    _snack('បានចម្លងទីតាំង៖ $text');
  }

  void _removeFavorite(FavoritePlace f) {
    final index = _favorites.indexWhere((e) => e.placeId == f.placeId);
    if (index < 0) return;
    setState(() => _favorites.removeAt(index));

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              'បានលុប «${f.name}» ចេញពីចំណាំ',
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'មិនធ្វើវិញ',
              textColor: AppColors.secondaryColor,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _favorites.insert(index.clamp(0, _favorites.length), f);
                });
              },
            ),
          ),
        )
        .closed
        .then((reason) {
          // Commit the deletion only if the user did not tap "undo".
          if (reason != SnackBarClosedReason.action) {
            _service.remove(f.placeId);
          }
        });
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF243456),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'លុបចំណាំទាំងអស់?',
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'ទីកន្លែងដែលបានរក្សាទុកទាំង ${_favorites.length} នឹងត្រូវបានយកចេញ។',
          style: GoogleFonts.notoSansKhmer(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'បោះបង់',
              style: GoogleFonts.notoSansKhmer(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'លុបទាំងអស់',
              style: GoogleFonts.notoSansKhmer(
                color: AppColors.alertBorderColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.clear();
    if (!mounted) return;
    setState(() => _favorites = []);
    _snack('បានលុបចំណាំទាំងអស់');
  }

  void _openDetail(FavoritePlace f, String? distanceLabel) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FavoritePlaceSheet(favorite: f, distanceLabel: distanceLabel),
    );
    if (result == kFavSheetRemove) _removeFavorite(f);
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          message,
          style: GoogleFonts.notoSansKhmer(fontSize: 13),
        ),
      ),
    );
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('ចំណាំ'));
  }
}

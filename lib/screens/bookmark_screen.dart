import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/favorite_route.dart';
import '../models/route_search_selection.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/favorite_routes_service.dart';
import '../services/favorites_service.dart';
import '../utils/constants/colors.dart';
import '../utils/constants/text_strings.dart';
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
  bool _hasError = false;

  // Favorite routes.
  List<FavoriteRoute> _routes = [];
  bool _routesLoading = true;
  bool _hasRoutesError = false;

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
    setState(() => _hasError = false);
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
        _hasError = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadRoutes() async {
    setState(() => _hasRoutesError = false);
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
        _hasRoutesError = true;
        _routesLoading = false;
      });
    }
  }

  // ---------- Derived data ----------

  double _metersFrom(FavoritePlace f, LatLng user) =>
      _distance.as(LengthUnit.Meter, user, LatLng(f.latitude, f.longitude));

  String? _distanceLabel(FavoritePlace f, LatLng? user, AppTexts t) {
    if (user == null) return null;
    final meters = _metersFrom(f, user);
    if (meters < 950) return t.distanceMeters(meters.round());
    final km = meters / 1000;
    return t.distanceKm(km.toStringAsFixed(km < 10 ? 1 : 0));
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
        final lang = context.read<SettingsProvider>().languageCode;
        list.sort(
          (a, b) => a
              .localizedName(lang)
              .toLowerCase()
              .compareTo(b.localizedName(lang).toLowerCase()),
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
    _snack(context.read<SettingsProvider>().t.copiedLocation(text));
  }

  void _removeFavorite(FavoritePlace f) {
    final index = _favorites.indexWhere((e) => e.placeId == f.placeId);
    if (index < 0) return;
    setState(() => _favorites.removeAt(index));

    final settings = context.read<SettingsProvider>();
    final t = settings.t;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              t.removedFromBookmarks(f.localizedName(settings.languageCode)),
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: t.undo,
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
    final t = context.read<SettingsProvider>().t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF243456),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t.clearAllBookmarksTitle,
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          t.clearAllBookmarksBody(_favorites.length),
          style: GoogleFonts.notoSansKhmer(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              t.cancel,
              style: GoogleFonts.notoSansKhmer(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              t.deleteAll,
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
    _snack(t.allBookmarksCleared);
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

    final t = context.read<SettingsProvider>().t;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              t.routeRemovedFromBookmarks,
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: t.undo,
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
    final t = context.read<SettingsProvider>().t;
    context.read<MapProvider>().openFavoriteRoute(
      favoriteId: r.id,
      origin: RouteSearchSelection(
        label: r.origin.name.isEmpty ? t.startLabel : r.origin.name,
        location: r.origin.coordinates,
      ),
      destination: RouteSearchSelection(
        label: r.destination.name.isEmpty ? t.destinationLabel : r.destination.name,
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
  Widget build(BuildContext context) {
    final user = context.watch<MapProvider>().currentPosition;
    final t = context.watch<SettingsProvider>().t;
    final visible = _visibleFavorites(user);

    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            _header(t),
            _tabToggle(t),
            const SizedBox(height: 8),
            Expanded(
              child: _tab == _BookmarkTab.places
                  ? _placesTab(visible, user, t)
                  : _routesTab(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placesTab(List<FavoritePlace> visible, LatLng? user, AppTexts t) {
    return Column(
      children: [
        _listBanner(t),
        if (_categories.isNotEmpty) _categoryChips(t),
        const SizedBox(height: 4),
        Expanded(child: _body(visible, user, t)),
      ],
    );
  }

  /// Segmented control switching between saved places and saved routes.
  Widget _tabToggle(AppTexts t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          _tabButton(
            label: t.placesTab,
            icon: Icons.place_outlined,
            selected: _tab == _BookmarkTab.places,
            onTap: () => setState(() => _tab = _BookmarkTab.places),
          ),
          const SizedBox(width: 8),
          _tabButton(
            label: t.routesTab,
            icon: Icons.directions_bus_outlined,
            selected: _tab == _BookmarkTab.routes,
            onTap: () => setState(() => _tab = _BookmarkTab.routes),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? AppColors.secondaryColor : kFavSurfaceColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.secondaryColor : kFavBorderColor,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.primaryColor : Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.notoSansKhmer(
                    color: selected ? AppColors.primaryColor : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _routesTab(AppTexts t) {
    if (_routesLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondaryColor),
      );
    }
    if (_hasRoutesError) {
      return _stateMessage(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadSavedRoutes,
        actionLabel: t.tryAgain,
        onAction: () {
          setState(() => _routesLoading = true);
          _loadRoutes();
        },
      );
    }
    if (_routes.isEmpty) {
      return _stateMessage(
        icon: Icons.bookmark_added_outlined,
        title: t.noSavedRoutes,
        subtitle: t.noSavedRoutesHint,
      );
    }
    return RefreshIndicator(
      color: AppColors.secondaryColor,
      backgroundColor: const Color(0xFF243456),
      onRefresh: _loadRoutes,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final route = _routes[i];
          return Dismissible(
            key: ValueKey('favroute_${route.id}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeRoute(route),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: AppColors.alertBorderColor.withAlpha(60),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.bookmark_remove_outlined,
                color: AppColors.alertBorderColor,
              ),
            ),
            child: FavoriteRouteCard(
              favorite: route,
              onTap: () => _openRouteDetail(route),
              onRemove: () => _removeRoute(route),
            ),
          );
        },
      ),
    );
  }

  Widget _header(AppTexts t) {
    final hasLocation = context.read<MapProvider>().currentPosition != null;
    final isPlaces = _tab == _BookmarkTab.places;
    final count = isPlaces ? _favorites.length : _routes.length;
    final loading = isPlaces ? _loading : _routesLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPlaces ? t.favoritePlaces : t.favoriteRoutes,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loading
                      ? t.loading
                      : isPlaces
                      ? t.savedPlacesCount(count)
                      : t.savedRoutesCount(count),
                  style: GoogleFonts.notoSansKhmer(
                    color: AppColors.secondaryTextColor,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (isPlaces) _sortMenu(hasLocation, t),
        ],
      ),
    );
  }

  Widget _sortMenu(bool hasLocation, AppTexts t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_rounded, color: Colors.white),
      color: const Color(0xFF243456),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tooltip: t.sort,
      onSelected: (value) {
        if (value == 'clear') {
          _confirmClearAll();
        } else {
          setState(() => _sort = value);
        }
      },
      itemBuilder: (_) => [
        _sortItem('recent', t.sortRecent),
        _sortItem('name', t.sortName),
        _sortItem('rating', t.sortRating),
        if (hasLocation) _sortItem('distance', t.sortDistance),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'clear',
          enabled: _favorites.isNotEmpty,
          child: Row(
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: _favorites.isEmpty
                    ? Colors.white24
                    : AppColors.alertBorderColor,
              ),
              const SizedBox(width: 10),
              Text(
                t.deleteAll,
                style: GoogleFonts.notoSansKhmer(
                  color: _favorites.isEmpty
                      ? Colors.white24
                      : AppColors.alertBorderColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    final selected = _sort == value;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? AppColors.secondaryColor : Colors.white38,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.notoSansKhmer(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  /// Google-Maps-style "list" header card sitting above the entries.
  Widget _listBanner(AppTexts t) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF243456), Color(0xFF1A2A4C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: kFavBorderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.secondaryColor, Color(0xFFE3C9A3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.primaryColor,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.myFavoritesList,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 13,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      t.privateListCount(_favorites.length),
                      style: GoogleFonts.notoSansKhmer(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white38),
        ],
      ),
    );
  }

  Widget _categoryChips(AppTexts t) {
    final categories = _categories;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(
            label: t.all,
            selected: _categoryFilter == null,
            onTap: () => setState(() => _categoryFilter = null),
          ),
          for (final c in categories)
            _chip(
              label: formatCategoryLabel(c),
              selected: _categoryFilter == c,
              onTap: () => setState(
                () => _categoryFilter = _categoryFilter == c ? null : c,
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.secondaryColor : kFavSurfaceColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.secondaryColor : kFavBorderColor,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.notoSansKhmer(
                color: selected ? AppColors.primaryColor : Colors.white70,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<FavoritePlace> visible, LatLng? user, AppTexts t) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondaryColor),
      );
    }
    if (_hasError) {
      return _stateMessage(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadSavedPlaces,
        actionLabel: t.tryAgain,
        onAction: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_favorites.isEmpty) {
      return _stateMessage(
        icon: Icons.bookmark_added_outlined,
        title: t.noSavedPlaces,
        subtitle: t.noSavedPlacesHint,
      );
    }
    if (visible.isEmpty) {
      return _stateMessage(
        icon: Icons.filter_alt_off_outlined,
        title: t.noPlacesInCategory,
        actionLabel: t.showAll,
        onAction: () => setState(() => _categoryFilter = null),
      );
    }

    return RefreshIndicator(
      color: AppColors.secondaryColor,
      backgroundColor: const Color(0xFF243456),
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final fav = visible[i];
          final distanceLabel = _distanceLabel(fav, user, t);
          return Dismissible(
            key: ValueKey('fav_${fav.placeId}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeFavorite(fav),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: AppColors.alertBorderColor.withAlpha(60),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.bookmark_remove_outlined,
                color: AppColors.alertBorderColor,
              ),
            ),
            child: FavoritePlaceCard(
              favorite: fav,
              distanceLabel: distanceLabel,
              onTap: () => _openDetail(fav, distanceLabel),
              onRemove: () => _removeFavorite(fav),
              onCopy: () => _copyCoordinates(fav),
            ),
          );
        },
      ),
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondaryColor.withAlpha(28),
              ),
              child: Icon(icon, size: 46, color: AppColors.secondaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKhmer(
                  color: AppColors.secondaryTextColor,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: AppColors.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: Text(
                  actionLabel,
                  style: GoogleFonts.notoSansKhmer(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

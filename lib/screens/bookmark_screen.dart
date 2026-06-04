import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../providers/map_provider.dart';
import '../services/auth_service.dart';
import '../services/favorites_service.dart';
import '../utils/constants/colors.dart';
import '../widgets/bookmark_screen/favorite_place_card.dart';
import '../widgets/bookmark_screen/favorite_place_sheet.dart';

/// "Saved places" screen — the user's favourite places, presented in the
/// style of the Google Maps *Saved* tab: a list-header banner, category
/// filter chips, sortable cards, swipe-to-remove and a detail sheet.
class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

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
    final user = context.watch<MapProvider>().currentPosition;
    final visible = _visibleFavorites(user);

    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _listBanner(),
            if (_categories.isNotEmpty) _categoryChips(),
            const SizedBox(height: 4),
            Expanded(child: _body(visible, user)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final hasLocation =
        context.read<MapProvider>().currentPosition != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ទីកន្លែងពេញចិត្ត',
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _loading
                      ? 'កំពុងផ្ទុក...'
                      : '${_favorites.length} ទីកន្លែងបានរក្សាទុក',
                  style: GoogleFonts.notoSansKhmer(
                    color: AppColors.secondaryTextColor,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          _sortMenu(hasLocation),
        ],
      ),
    );
  }

  Widget _sortMenu(bool hasLocation) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune_rounded, color: Colors.white),
      color: const Color(0xFF243456),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tooltip: 'តម្រៀប',
      onSelected: (value) {
        if (value == 'clear') {
          _confirmClearAll();
        } else {
          setState(() => _sort = value);
        }
      },
      itemBuilder: (_) => [
        _sortItem('recent', 'ថ្មីៗបំផុត'),
        _sortItem('name', 'តាមឈ្មោះ (ក-អ)'),
        _sortItem('rating', 'ការវាយតម្លៃខ្ពស់'),
        if (hasLocation) _sortItem('distance', 'ចម្ងាយជិតបំផុត'),
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
                'លុបទាំងអស់',
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
  Widget _listBanner() {
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
                  'បញ្ជីចំណូលចិត្តរបស់ខ្ញុំ',
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 13, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      'បញ្ជីឯកជន · ${_favorites.length} ទីកន្លែង',
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

  Widget _categoryChips() {
    final categories = _categories;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip(
            label: 'ទាំងអស់',
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

  Widget _body(List<FavoritePlace> visible, LatLng? user) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondaryColor),
      );
    }
    if (_error != null) {
      return _stateMessage(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        actionLabel: 'ព្យាយាមម្ដងទៀត',
        onAction: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_favorites.isEmpty) {
      return _stateMessage(
        icon: Icons.bookmark_added_outlined,
        title: 'មិនទាន់មានទីកន្លែងដែលបានរក្សាទុក',
        subtitle:
            'ប៉ះរូបតំណាងចំណាំនៅលើទីកន្លែងណាមួយក្នុងផែនទី ដើម្បីរក្សាទុកវានៅទីនេះ។',
      );
    }
    if (visible.isEmpty) {
      return _stateMessage(
        icon: Icons.filter_alt_off_outlined,
        title: 'គ្មានទីកន្លែងក្នុងប្រភេទនេះ',
        actionLabel: 'បង្ហាញទាំងអស់',
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
          final distanceLabel = _distanceLabel(fav, user);
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

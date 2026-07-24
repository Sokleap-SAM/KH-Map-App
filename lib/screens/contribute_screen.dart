import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/contribution.dart';
import '../models/place.dart';
import '../providers/map_provider.dart';
import '../providers/settings_provider.dart';
import '../services/auth_service.dart';
import '../services/contribution_service.dart';
import '../utils/auth_guard.dart';
import '../utils/constants/colors.dart';
import '../utils/constants/text_strings.dart';
import '../utils/place_request_status.dart';
import '../utils/theme/app_palette.dart';
import '../widgets/bookmark_screen/favorite_place_card.dart';
import '../widgets/contribute_screen/contribution_card.dart';
import '../widgets/contribute_screen/contribution_form.dart';
import '../widgets/contribute_screen/contribution_sheet.dart';
import '../widgets/contribute_screen/my_requests_sheet.dart';

/// "My Contributions" — the user's reviews, photos and self-created places,
/// styled like the saved-places tab (header, banner, category chips, list).
class ContributeScreen extends StatefulWidget {
  const ContributeScreen({super.key});

  @override
  State<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends State<ContributeScreen> {
  final ContributionService _service = ContributionService();
  final Distance _distance = const Distance();

  List<Contribution> _contributions = [];
  bool _loading = true;
  bool _hasError = false;

  // Server-side place requests, keyed by placeId for inline status badges, plus
  // the "already seen" set that drives the notification bell count.
  List<Place> _requests = const [];
  Map<String, String> _statusByPlaceId = const {};
  Set<String> _seenRequestIds = const {};

  String? _categoryFilter;
  String _sort = 'recent'; // recent | rating | name | distance

  @override
  void initState() {
    super.initState();
    _load();
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
      _contributions = [];
      _loading = true;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _hasError = false);
    try {
      final list = await _service.load();
      if (!mounted) return;
      setState(() {
        _contributions = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _loading = false;
      });
    }
    // Merge the server-side copy of this account's contributions back in
    // (best-effort, non-blocking for the locally-loaded list above).
    _syncWithBackend();
  }

  /// Merges the account's database-side contributions (place requests created
  /// by the user + ratings they left) into the local list, and pulls the
  /// request statuses plus the set of already-seen resolved requests that
  /// drive the inline badges and the bell.
  Future<void> _syncWithBackend() async {
    final result = await _service.syncWithBackend();
    final seen = await _service.acknowledgedRequestIds();
    if (!mounted) return;
    setState(() {
      _contributions = result.contributions;
      _requests = result.requests;
      _statusByPlaceId = {for (final p in result.requests) p.id: p.status};
      _seenRequestIds = seen;
      _loading = false;
    });
  }

  /// Approved/rejected requests the user hasn't viewed yet — the bell badge.
  int get _unseenResolvedCount => _requests
      .where((p) =>
          isPlaceStatusResolved(p.status) && !_seenRequestIds.contains(p.id))
      .length;

  Future<void> _openRequests() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MyRequestsSheet(requests: _requests),
    );
    // Viewing the sheet acknowledges every resolved request → clears the badge.
    final resolved = _requests
        .where((p) => isPlaceStatusResolved(p.status))
        .map((p) => p.id)
        .toList();
    await _service.acknowledgeRequests(resolved);
    if (!mounted) return;
    setState(() => _seenRequestIds = {..._seenRequestIds, ...resolved});
  }

  // ─── Derived data ─────────────────────────────────────────────────────────

  double _metersFrom(Contribution c, LatLng user) =>
      _distance.as(LengthUnit.Meter, user, LatLng(c.latitude, c.longitude));

  String? _distanceLabel(Contribution c, LatLng? user, AppTexts t) {
    if (user == null) return null;
    final meters = _metersFrom(c, user);
    if (meters < 950) return t.distanceMeters(meters.round());
    final km = meters / 1000;
    return t.distanceKm(km.toStringAsFixed(km < 10 ? 1 : 0));
  }

  List<String> get _categories {
    final seen = <String>{};
    for (final c in _contributions) {
      if (c.categoryName.trim().isNotEmpty) seen.add(c.categoryName);
    }
    final list = seen.toList()..sort();
    return list;
  }

  List<Contribution> _visible(LatLng? user) {
    final list = _contributions
        .where((c) =>
            _categoryFilter == null || c.categoryName == _categoryFilter)
        .toList();
    switch (_sort) {
      case 'rating':
        list.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'name':
        final lang = context.read<SettingsProvider>().languageCode;
        list.sort(
          (a, b) => a.localizedPlaceLabel(lang).toLowerCase().compareTo(
                b.localizedPlaceLabel(lang).toLowerCase(),
              ),
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
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  // ─── Counters for the banner ──────────────────────────────────────────────

  int get _totalPhotos =>
      _contributions.fold(0, (sum, c) => sum + c.photos.length);
  int get _newPlaces => _contributions.where((c) => c.isCustomPlace).length;
  double? get _averageRating {
    final rated = _contributions.where((c) => c.rating > 0).toList();
    if (rated.isEmpty) return null;
    final sum = rated.fold<double>(0, (s, c) => s + c.rating);
    return sum / rated.length;
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _openForm({Contribution? initial}) async {
    // Guests can't contribute: their submissions never reach the backend, so
    // gate the form behind sign-in and send them to the login page first.
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;
    final saved = await showModalBottomSheet<Contribution>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContributionForm(service: _service, initial: initial),
    );
    // Always reload: the save may have completed in the background even if the
    // sheet was swiped away before Navigator.pop fired (making saved == null).
    await _load();
    if (!mounted) return;
    if (saved != null) {
      // Refresh map places so any updated average rating is reflected. A newly
      // submitted custom place stays hidden until an admin approves it.
      context.read<MapProvider>().loadPlaces();
      final t = context.read<SettingsProvider>().t;
      final String message;
      if (initial != null) {
        message = t.contributionUpdated;
      } else if (saved.isCustomPlace) {
        message = t.placeRequestSubmitted;
      } else {
        message = t.contributionSaved;
      }
      _snack(message);
    }
  }

  void _openDetail(Contribution c, String? distanceLabel) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ContributionSheet(
        contribution: c,
        distanceLabel: distanceLabel,
      ),
    );
    if (result == kContribSheetRemove) {
      _removeContribution(c);
    } else if (result == kContribSheetEdit) {
      _openForm(initial: c);
    }
  }

  void _removeContribution(Contribution c) {
    final index = _contributions.indexWhere((e) => e.id == c.id);
    if (index < 0) return;
    setState(() => _contributions.removeAt(index));

    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            content: Text(
              settings.t.contributionRemoved(
                c.localizedPlaceLabel(settings.languageCode),
              ),
              style: GoogleFonts.notoSansKhmer(fontSize: 13),
            ),
            action: SnackBarAction(
              label: settings.t.undo,
              textColor: AppColors.secondaryColor,
              onPressed: () {
                if (!mounted) return;
                setState(() {
                  _contributions.insert(
                    index.clamp(0, _contributions.length),
                    c,
                  );
                });
              },
            ),
          ),
        )
        .closed
        .then((reason) async {
      if (reason != SnackBarClosedReason.action) {
        await _service.remove(c.id);
        if (mounted) context.read<MapProvider>().loadPlaces();
      }
    });
  }

  Future<void> _confirmClearAll() async {
    final t = context.read<SettingsProvider>().t;
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          t.clearAllContributionsTitle,
          style: GoogleFonts.notoSansKhmer(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          t.clearAllContributionsBody(_contributions.length),
          style: GoogleFonts.notoSansKhmer(
            color: p.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              t.cancel,
              style: GoogleFonts.notoSansKhmer(color: p.textSecondary),
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
    setState(() => _contributions = []);
    _snack(t.allContributionsCleared);
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<MapProvider>().currentPosition;
    final t = context.watch<SettingsProvider>().t;
    final visible = _visible(user);

    return Scaffold(
      backgroundColor: context.palette.scaffold,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'contribute_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: AppColors.primaryColor,
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          t.navContribute,
          style: GoogleFonts.notoSansKhmer(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _header(t),
            _listBanner(t),
            if (_categories.isNotEmpty) _categoryChips(t),
            const SizedBox(height: 4),
            Expanded(child: _body(visible, user, t)),
          ],
        ),
      ),
    );
  }

  Widget _header(AppTexts t) {
    final hasLocation = context.read<MapProvider>().currentPosition != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.myContributions,
                  style: GoogleFonts.notoSansKhmer(
                    color: context.palette.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _loading
                      ? t.loading
                      : t.contributionsCount(_contributions.length),
                  style: GoogleFonts.notoSansKhmer(
                    color: context.palette.subtitle,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          _notificationBell(t),
          _sortMenu(hasLocation, t),
        ],
      ),
    );
  }

  Widget _notificationBell(AppTexts t) {
    final count = _unseenResolvedCount;
    return IconButton(
      tooltip: t.myPlaceRequests,
      onPressed: _openRequests,
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppColors.alertBorderColor,
        child: Icon(Icons.notifications_outlined, color: context.palette.textPrimary),
      ),
    );
  }

  Widget _sortMenu(bool hasLocation, AppTexts t) {
    final p = context.palette;
    return PopupMenuButton<String>(
      icon: Icon(Icons.tune_rounded, color: p.textPrimary),
      color: p.surface,
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
        _sortItem('rating', t.sortRating),
        _sortItem('name', t.sortName),
        if (hasLocation) _sortItem('distance', t.sortDistance),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'clear',
          enabled: _contributions.isNotEmpty,
          child: Row(
            children: [
              Icon(
                Icons.delete_sweep_outlined,
                size: 18,
                color: _contributions.isEmpty
                    ? p.textFaintest
                    : AppColors.alertBorderColor,
              ),
              const SizedBox(width: 10),
              Text(
                t.deleteAll,
                style: GoogleFonts.notoSansKhmer(
                  color: _contributions.isEmpty
                      ? p.textFaintest
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
    final p = context.palette;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? AppColors.secondaryColor : p.textFaintest,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.notoSansKhmer(
              color: selected ? p.textPrimary : p.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listBanner(AppTexts t) {
    final p = context.palette;
    final avg = _averageRating;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [p.surface, p.surfaceAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  Icons.workspace_premium_rounded,
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
                      t.communityContributor,
                      style: GoogleFonts.notoSansKhmer(
                        color: p.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.public_rounded,
                          size: 13,
                          color: p.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.contributionTypesLine,
                          style: GoogleFonts.notoSansKhmer(
                            color: p.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(
                icon: Icons.star_rounded,
                color: const Color(0xFFFFB400),
                label: t.statAverage,
                value: avg == null ? '—' : avg.toStringAsFixed(1),
              ),
              const SizedBox(width: 12),
              _stat(
                icon: Icons.photo_camera_outlined,
                color: AppColors.secondaryColor,
                label: t.photos,
                value: '$_totalPhotos',
              ),
              const SizedBox(width: 12),
              _stat(
                icon: Icons.add_location_alt_outlined,
                color: AppColors.buttonCategoryBlueColor,
                label: t.statNewPlaces,
                value: '$_newPlaces',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.notoSansKhmer(
                color: p.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.notoSansKhmer(
                color: p.textFaint,
                fontSize: 11,
              ),
            ),
          ],
        ),
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
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.secondaryColor : p.surfaceAlt,
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
                color: selected ? AppColors.secondaryColor : p.border,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.notoSansKhmer(
                color: selected ? AppColors.primaryColor : p.textSecondary,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(List<Contribution> visible, LatLng? user, AppTexts t) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondaryColor),
      );
    }
    if (_hasError) {
      return _stateMessage(
        icon: Icons.cloud_off_rounded,
        title: t.couldNotLoadContributions,
        actionLabel: t.tryAgain,
        onAction: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_contributions.isEmpty) {
      return _stateMessage(
        icon: Icons.rate_review_outlined,
        title: t.noContributionsYet,
        subtitle: t.noContributionsHint,
        actionLabel: t.contributeNow,
        onAction: () => _openForm(),
      );
    }
    if (visible.isEmpty) {
      return _stateMessage(
        icon: Icons.filter_alt_off_outlined,
        title: t.noContributionsInCategory,
        actionLabel: t.showAll,
        onAction: () => setState(() => _categoryFilter = null),
      );
    }

    return RefreshIndicator(
      color: AppColors.secondaryColor,
      backgroundColor: context.palette.surface,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final c = visible[i];
          final dist = _distanceLabel(c, user, t);
          return Dismissible(
            key: ValueKey('contrib_${c.id}'),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeContribution(c),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: AppColors.alertBorderColor.withAlpha(60),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.alertBorderColor,
              ),
            ),
            child: ContributionCard(
              contribution: c,
              distanceLabel: dist,
              requestStatus: c.isCustomPlace && c.placeId != null
                  ? _statusByPlaceId[c.placeId]
                  : null,
              onTap: () => _openDetail(c, dist),
              onRemove: () => _removeContribution(c),
              onEdit: () => _openForm(initial: c),
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
    final p = context.palette;
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
                color: p.textPrimary,
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
                  color: p.subtitle,
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

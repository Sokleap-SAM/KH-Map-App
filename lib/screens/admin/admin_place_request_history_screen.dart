import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/place_request_status.dart';
import '../../utils/theme/app_palette.dart';
import '../../widgets/bookmark_screen/favorite_place_card.dart';
import 'admin_place_request_detail_screen.dart';

/// Read-only admin review log: every place request that has been approved or
/// rejected, most-recently-reviewed first. Opened from the history button on
/// the pending-requests screen. A filter row narrows to approved / rejected.
class AdminPlaceRequestHistoryScreen extends StatefulWidget {
  const AdminPlaceRequestHistoryScreen({super.key});

  @override
  State<AdminPlaceRequestHistoryScreen> createState() =>
      _AdminPlaceRequestHistoryScreenState();
}

enum _HistoryFilter { all, approved, rejected }

class _AdminPlaceRequestHistoryScreenState
    extends State<AdminPlaceRequestHistoryScreen> {
  final AdminService _service = AdminService();

  List<Place> _all = const [];
  bool _loading = true;
  String? _error;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final history = await _service.fetchPlaceRequestHistory();
      if (!mounted) return;
      setState(() {
        _all = history;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  /// Opens the full detail screen where the admin can review the place and,
  /// via the status-change action bar, flip an approved request to rejected or
  /// vice versa. Refetches on return so the new status/reviewer is reflected.
  Future<void> _openDetail(Place p) async {
    final decision = await Navigator.of(context).push<AdminRequestDecision>(
      MaterialPageRoute(
        builder: (_) => AdminPlaceRequestDetailScreen(place: p),
      ),
    );
    if (decision == null || !mounted) return;
    final settings = context.read<SettingsProvider>();
    final t = settings.t;
    final name = p.localizedName(settings.languageCode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t.changedTo(
            name,
            decision == AdminRequestDecision.approved
                ? t.statusApproved
                : t.statusRejected,
          ),
        ),
      ),
    );
    await _load();
  }

  List<Place> get _visible {
    switch (_filter) {
      case _HistoryFilter.approved:
        return _all.where((p) => p.isApproved).toList();
      case _HistoryFilter.rejected:
        return _all.where((p) => p.isRejected).toList();
      case _HistoryFilter.all:
        return _all;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.reviewHistory),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(t),
          const Divider(height: 1),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _filterBar(AppTexts t) {
    final approved = _all.where((p) => p.isApproved).length;
    final rejected = _all.where((p) => p.isRejected).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          _filterChip(t.filterAll(_all.length), _HistoryFilter.all),
          const SizedBox(width: 8),
          _filterChip(t.filterApproved(approved), _HistoryFilter.approved),
          const SizedBox(width: 8),
          _filterChip(t.filterRejected(rejected), _HistoryFilter.rejected),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _HistoryFilter value) {
    final selected = _filter == value;
    final pal = context.palette;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: pal.accent,
      labelStyle: TextStyle(
        color: selected ? pal.onAccent : pal.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: Text(t.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Icon(
              Icons.history_toggle_off,
              size: 64,
              color: context.palette.textFaintest,
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                t.noHistoryYet,
                style: TextStyle(
                  color: context.palette.textSecondary,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _historyCard(visible[i]),
      ),
    );
  }

  Widget _historyCard(Place p) {
    final settings = context.watch<SettingsProvider>();
    final t = settings.t;
    final color = getColorForCategory(p.category?.name);
    final icon = getIconForCategory(p.category?.name);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: p.photos.isNotEmpty
                    ? Image.network(
                        p.photos.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _iconTile(icon, color),
                      )
                    : _iconTile(icon, color),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          p.localizedName(settings.languageCode),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PlaceStatusChip(status: p.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(icon, size: 14, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          formatCategoryLabel(p.category?.name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.palette.subtitle,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (p.createdByName != null) ...[
                    const SizedBox(height: 4),
                    _metaRow(
                      Icons.person_outline,
                      t.submittedByName(p.createdByName!),
                    ),
                  ],
                  if (p.reviewedAt != null) ...[
                    const SizedBox(height: 2),
                    _metaRow(
                      Icons.schedule,
                      p.reviewedByName != null
                          ? t.reviewedAgoBy(p.reviewedAt!, p.reviewedByName!)
                          : t.reviewedAgo(p.reviewedAt!),
                    ),
                  ] else if (p.createdAt != null) ...[
                    const SizedBox(height: 2),
                    _metaRow(Icons.schedule, t.submittedAgo(p.createdAt!)),
                  ],
                  if (p.isRejected && p.rejectionReason != null) ...[
                    const SizedBox(height: 8),
                    _rejectionReason(t, p.rejectionReason!),
                  ],
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _rejectionReason(AppTexts t, String reason) {
    final color = AppColors.alertBorderColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.rejectionReasonLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: context.palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    final pal = context.palette;
    return Row(
      children: [
        Icon(icon, size: 13, color: pal.textFaintest),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: pal.textFaint),
          ),
        ),
      ],
    );
  }

  Widget _iconTile(IconData icon, Color color) {
    return Container(
      color: color.withAlpha(40),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 26),
    );
  }

}

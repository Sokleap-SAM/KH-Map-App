import 'package:flutter/material.dart';

import '../../models/place.dart';
import '../../services/admin_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/place_request_status.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          decision == AdminRequestDecision.approved
              ? 'បានប្ដូរ «${p.name}» ទៅ បានអនុម័ត'
              : 'បានប្ដូរ «${p.name}» ទៅ បានបដិសេធ',
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('ប្រវត្តិការត្រួតពិនិត្យ (History)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'ផ្ទុកឡើងវិញ (Refresh)',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _filterBar(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final approved = _all.where((p) => p.isApproved).length;
    final rejected = _all.where((p) => p.isRejected).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          _filterChip('ទាំងអស់ (${_all.length})', _HistoryFilter.all),
          const SizedBox(width: 8),
          _filterChip('បានអនុម័ត ($approved)', _HistoryFilter.approved),
          const SizedBox(width: 8),
          _filterChip('បានបដិសេធ ($rejected)', _HistoryFilter.rejected),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _HistoryFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primaryColor,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  Widget _buildBody() {
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
                child: const Text('ព្យាយាមម្ដងទៀត'),
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
          children: const [
            SizedBox(height: 120),
            Icon(Icons.history_toggle_off, size: 64, color: Colors.black26),
            SizedBox(height: 12),
            Center(
              child: Text(
                'គ្មានប្រវត្តិទេ',
                style: TextStyle(color: Colors.black54, fontSize: 15),
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
                          p.name,
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
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (p.createdByName != null) ...[
                    const SizedBox(height: 4),
                    _metaRow(
                      Icons.person_outline,
                      'ស្នើដោយ ${p.createdByName}',
                    ),
                  ],
                  if (p.reviewedAt != null) ...[
                    const SizedBox(height: 2),
                    _metaRow(
                      Icons.schedule,
                      p.reviewedByName != null
                          ? 'ត្រួតពិនិត្យ ${_ago(p.reviewedAt!)} ដោយ ${p.reviewedByName}'
                          : 'ត្រួតពិនិត្យ ${_ago(p.reviewedAt!)}',
                    ),
                  ] else if (p.createdAt != null) ...[
                    const SizedBox(height: 2),
                    _metaRow(Icons.schedule, 'ស្នើ ${_ago(p.createdAt!)}'),
                  ],
                  if (p.isRejected && p.rejectionReason != null) ...[
                    const SizedBox(height: 8),
                    _rejectionReason(p.rejectionReason!),
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

  Widget _rejectionReason(String reason) {
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
                  'មូលហេតុនៃការបដិសេធ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reason,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.black38),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.black45),
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

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inDays >= 1) return '${diff.inDays} ថ្ងៃមុន';
    if (diff.inHours >= 1) return '${diff.inHours} ម៉ោងមុន';
    if (diff.inMinutes >= 1) return '${diff.inMinutes} នាទីមុន';
    return 'អម្បាញ់មិញ';
  }
}

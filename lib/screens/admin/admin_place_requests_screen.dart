import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../widgets/admin/reject_reason_dialog.dart';
import '../../widgets/bookmark_screen/favorite_place_card.dart';
import 'admin_place_request_detail_screen.dart';
import 'admin_place_request_history_screen.dart';

/// Admin review queue for user-submitted place requests. Lists every PENDING
/// place with its details and photos; the admin approves (publishes it to the
/// map) or rejects (keeps it hidden, flagged for the submitter).
class AdminPlaceRequestsScreen extends StatefulWidget {
  const AdminPlaceRequestsScreen({super.key});

  @override
  State<AdminPlaceRequestsScreen> createState() =>
      _AdminPlaceRequestsScreenState();
}

class _AdminPlaceRequestsScreenState extends State<AdminPlaceRequestsScreen> {
  final AdminService _service = AdminService();

  List<Place> _requests = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final requests = await _service.fetchPendingPlaceRequests();
      if (!mounted) return;
      setState(() {
        _requests = requests;
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

  Future<void> _approve(Place p) => _act(p, approve: true);

  Future<void> _reject(Place p) async {
    final reason = await showRejectReasonDialog(
      context,
      placeName: p.localizedName(context.read<SettingsProvider>().languageCode),
    );
    if (reason == null || !mounted) return;
    await _act(p, approve: false, reason: reason);
  }

  Future<void> _act(Place p, {required bool approve, String? reason}) async {
    final settings = context.read<SettingsProvider>();
    final t = settings.t;
    final name = p.localizedName(settings.languageCode);
    setState(() => _processing.add(p.id));
    try {
      if (approve) {
        await _service.approvePlaceRequest(p.id);
      } else {
        await _service.rejectPlaceRequest(p.id, reason!);
      }
      if (!mounted) return;
      setState(() {
        _requests = _requests.where((r) => r.id != p.id).toList();
        _processing.remove(p.id);
      });
      _snack(approve ? t.approvedShown(name) : t.rejectedName(name));
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing.remove(p.id));
      final msg = e is AdminApiException ? e.message : e.toString();
      _snack(t.failedWith(msg));
    }
  }

  Future<void> _openDetail(Place p) async {
    final decision = await Navigator.of(context).push<AdminRequestDecision>(
      MaterialPageRoute(
        builder: (_) => AdminPlaceRequestDetailScreen(place: p),
      ),
    );
    if (decision == null || !mounted) return;
    final settings = context.read<SettingsProvider>();
    final name = p.localizedName(settings.languageCode);
    setState(() {
      _requests = _requests.where((r) => r.id != p.id).toList();
      _processing.remove(p.id);
    });
    _snack(
      decision == AdminRequestDecision.approved
          ? settings.t.approvedShown(name)
          : settings.t.rejectedName(name),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          _requests.isEmpty
              ? t.placeRequestsTitle
              : t.placeRequestsTitleCount(_requests.length),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: t.history,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminPlaceRequestHistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _requests.isEmpty) {
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
    if (_requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            const Icon(Icons.inbox_outlined, size: 64, color: Colors.black26),
            const SizedBox(height: 12),
            Center(
              child: Text(
                t.noNewRequests,
                style: const TextStyle(color: Colors.black54, fontSize: 15),
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
        itemCount: _requests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _requestCard(_requests[i]),
      ),
    );
  }

  Widget _requestCard(Place p) {
    final settings = context.watch<SettingsProvider>();
    final t = settings.t;
    final color = getColorForCategory(p.category?.name);
    final icon = getIconForCategory(p.category?.name);
    final busy = _processing.contains(p.id);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => _openDetail(p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 60,
                    height: 60,
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
                      Text(
                        p.localizedName(settings.languageCode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
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
                      const SizedBox(height: 3),
                      Text(
                        '${p.latitude.toStringAsFixed(5)}, '
                        '${p.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.black45,
                        ),
                      ),
                      if (p.createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          t.submittedAgo(p.createdAt!),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (p.photos.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: p.photos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      p.photos[i],
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.black12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : () => _reject(p),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(t.reject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.alertBorderColor,
                      side: const BorderSide(color: AppColors.alertBorderColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _approve(p),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(t.approve),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF7D),
                    ),
                  ),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
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

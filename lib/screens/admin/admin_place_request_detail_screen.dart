import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/place_request_status.dart';
import '../../utils/theme/app_palette.dart';
import '../../widgets/admin/reject_reason_dialog.dart';
import '../../widgets/bookmark_screen/favorite_place_card.dart';

/// The decision an admin made on a place request, returned to the list so it
/// can update the row without a full refetch.
enum AdminRequestDecision { approved, rejected }

/// Full-screen detail for a single place request. Shows the submitted photos, a
/// map pin at the requested coordinates and every field the admin needs to
/// judge the place. Used both for the pending review queue (approve / reject)
/// and the review history, where an already-approved or -rejected request can
/// have its status changed.
class AdminPlaceRequestDetailScreen extends StatefulWidget {
  final Place place;

  const AdminPlaceRequestDetailScreen({super.key, required this.place});

  @override
  State<AdminPlaceRequestDetailScreen> createState() =>
      _AdminPlaceRequestDetailScreenState();
}

class _AdminPlaceRequestDetailScreenState
    extends State<AdminPlaceRequestDetailScreen> {
  final AdminService _service = AdminService();
  final PageController _photoController = PageController();

  bool _busy = false;
  // Which action is in flight, so only the pressed button shows a spinner.
  bool _actingApprove = false;
  int _currentPhoto = 0;

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _approve() => _act(approve: true);

  Future<void> _reject() async {
    final reason = await showRejectReasonDialog(
      context,
      placeName: widget.place.localizedName(
        context.read<SettingsProvider>().languageCode,
      ),
    );
    if (reason == null || !mounted) return;
    await _act(approve: false, reason: reason);
  }

  Future<void> _act({required bool approve, String? reason}) async {
    final p = widget.place;
    setState(() {
      _busy = true;
      _actingApprove = approve;
    });
    try {
      if (approve) {
        await _service.approvePlaceRequest(p.id);
      } else {
        await _service.rejectPlaceRequest(p.id, reason!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(
        approve ? AdminRequestDecision.approved : AdminRequestDecision.rejected,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SettingsProvider>().t.failedWith(msg)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final settings = context.watch<SettingsProvider>();
    final t = settings.t;
    final lang = settings.languageCode;
    final color = getColorForCategory(p.category?.name);
    final icon = getIconForCategory(p.category?.name);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(p.localizedName(lang), overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _photoHeader(p, icon, color),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.localizedName(lang),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PlaceStatusChip(status: p.status, fontSize: 12),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text(
                      formatCategoryLabel(p.category?.name),
                      style: TextStyle(
                        fontSize: 14,
                        color: context.palette.subtitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _infoTile(
            icon: Icons.category_outlined,
            label: t.category,
            value: formatCategoryLabel(p.category?.name),
          ),
          _infoTile(
            icon: Icons.location_on_outlined,
            label: t.coordinates,
            value:
                '${p.latitude.toStringAsFixed(6)}, '
                '${p.longitude.toStringAsFixed(6)}',
          ),
          _infoTile(
            icon: Icons.star_outline,
            label: t.rating,
            value: p.averageRating != null
                ? '${p.averageRating!.toStringAsFixed(1)} '
                      '· ${t.ratingsCount(p.ratingCount ?? 0)}'
                : t.notYet,
          ),
          if (p.createdByName != null)
            _infoTile(
              icon: Icons.person_outline,
              label: t.submittedBy,
              value: p.createdByName!,
            ),
          if (p.createdAt != null)
            _infoTile(
              icon: Icons.schedule,
              label: t.submittedAt,
              value: t.submittedAgo(p.createdAt!),
            ),
          if (p.reviewedAt != null)
            _infoTile(
              icon: Icons.rule,
              label: t.reviewedLabel,
              value: p.reviewedByName != null
                  ? t.timeAgoBy(p.reviewedAt!, p.reviewedByName!)
                  : t.timeAgo(p.reviewedAt!),
            ),
          _infoTile(
            icon: Icons.photo_library_outlined,
            label: t.photos,
            value: '${p.photos.length}',
          ),
          if (p.isRejected && p.rejectionReason != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _rejectionReason(t, p.rejectionReason!),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              t.locationOnMap,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 220, child: _buildMap(p, icon, color)),
            ),
          ),
          const SizedBox(height: 20),
          _actionBar(t),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _photoHeader(Place p, IconData icon, Color color) {
    if (p.photos.isEmpty) {
      return Container(
        height: 200,
        color: color.withAlpha(38),
        alignment: Alignment.center,
        child: Icon(icon, size: 72, color: color),
      );
    }
    return SizedBox(
      height: 240,
      child: Stack(
        children: [
          PageView.builder(
            controller: _photoController,
            itemCount: p.photos.length,
            onPageChanged: (i) => setState(() => _currentPhoto = i),
            itemBuilder: (_, i) => Image.network(
              p.photos[i],
              fit: BoxFit.cover,
              width: double.infinity,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Container(
                      color: context.palette.surfaceAlt,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
              errorBuilder: (_, _, _) => Container(
                color: color.withAlpha(38),
                alignment: Alignment.center,
                child: Icon(icon, size: 72, color: color),
              ),
            ),
          ),
          if (p.photos.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(p.photos.length, (i) {
                  final active = i == _currentPhoto;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(Place p, IconData icon, Color color) {
    final point = LatLng(p.latitude, p.longitude);
    return FlutterMap(
      options: MapOptions(initialCenter: point, initialZoom: 15),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: point,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: Icon(Icons.location_on, size: 44, color: color),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rejectionReason(AppTexts t, String reason) {
    final color = AppColors.alertBorderColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_gmailerrorred_outlined, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.rejectionReasonLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 13.5,
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

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final pal = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: pal.textFaint),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: pal.textFaint),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Action bar for both the pending queue (approve / reject) and the history
  /// (change an already-reviewed status). The button matching the current
  /// status is disabled and marked as the active one so it reads as "current".
  Widget _actionBar(AppTexts t) {
    final p = widget.place;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.isPending ? t.reviewThisRequest : t.changeStatus,
            style: TextStyle(
              fontSize: 13,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _rejectButton(t, p)),
              const SizedBox(width: 12),
              Expanded(child: _approveButton(t, p)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rejectButton(AppTexts t, Place p) {
    final isCurrent = p.isRejected;
    final busy = _busy && !_actingApprove;
    return OutlinedButton.icon(
      onPressed: (_busy || isCurrent) ? null : _reject,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(isCurrent ? Icons.cancel : Icons.close, size: 18),
      label: Text(isCurrent ? t.statusRejected : t.reject),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: AppColors.alertBorderColor,
        side: const BorderSide(color: AppColors.alertBorderColor),
      ),
    );
  }

  Widget _approveButton(AppTexts t, Place p) {
    final isCurrent = p.isApproved;
    final busy = _busy && _actingApprove;
    return FilledButton.icon(
      onPressed: (_busy || isCurrent) ? null : _approve,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(isCurrent ? Icons.check_circle : Icons.check, size: 18),
      label: Text(isCurrent ? t.statusApproved : t.approve),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        backgroundColor: const Color(0xFF4CAF7D),
      ),
    );
  }
}

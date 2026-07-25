import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../providers/settings_provider.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/place_request_status.dart';
import '../../utils/theme/app_palette.dart';
import '../bookmark_screen/favorite_place_card.dart';

/// Read-only notifications sheet listing the user's submitted place requests
/// and the review outcome of each (pending / approved / rejected).
class MyRequestsSheet extends StatelessWidget {
  final List<Place> requests;

  const MyRequestsSheet({super.key, required this.requests});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              _handle(context),
              _header(context),
              Divider(color: context.palette.divider, height: 1),
              Expanded(
                child: requests.isEmpty
                    ? _empty(context)
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        itemCount: requests.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _requestTile(context, requests[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _handle(BuildContext context) => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.palette.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_active_outlined,
            color: AppColors.secondaryColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.myPlaceRequests,
                  style: GoogleFonts.notoSansKhmer(
                    color: context.palette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  t.newPlaceRequestStatus,
                  style: GoogleFonts.notoSansKhmer(
                    color: context.palette.subtitle,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: context.palette.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 56,
            color: AppColors.secondaryColor.withAlpha(120),
          ),
          const SizedBox(height: 12),
          Text(
            context.watch<SettingsProvider>().t.noRequestsYet,
            style: GoogleFonts.notoSansKhmer(
              color: context.palette.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestTile(BuildContext context, Place p) {
    final settings = context.watch<SettingsProvider>();
    final t = settings.t;
    final color = getColorForCategory(p.category?.name);
    final icon = getIconForCategory(p.category?.name);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 52,
              height: 52,
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
                  style: GoogleFonts.notoSansKhmer(
                    color: context.palette.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        formatCategoryLabel(p.category?.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKhmer(
                          color: context.palette.subtitle,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    PlaceStatusChip(status: p.status),
                    if (p.isRejected) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          t.notShownOnMap,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.notoSansKhmer(
                            color: context.palette.textFaintest,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (p.isRejected && p.rejectionReason != null) ...[
                  const SizedBox(height: 8),
                  _rejectionReason(context, t, p.rejectionReason!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rejectionReason(BuildContext context, AppTexts t, String reason) {
    const color = AppColors.alertBorderColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.report_gmailerrorred_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 5),
              Text(
                t.rejectionReasonLabel,
                style: GoogleFonts.notoSansKhmer(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            reason,
            style: GoogleFonts.notoSansKhmer(
              color: context.palette.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconTile(IconData icon, Color color) {
    return Container(
      color: color.withAlpha(45),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 24),
    );
  }
}

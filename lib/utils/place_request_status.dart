import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'constants/colors.dart';

/// Presentation helpers for a place request's approval status
/// ('pending' | 'approved' | 'rejected'). Shared by the admin review screen
/// and the user's contribution screen so the colours/labels stay consistent.
/// The localized status label lives on `AppTexts.placeStatusLabel`.

/// Accent colour for a status value.
Color placeStatusColor(String status) {
  switch (status) {
    case 'approved':
      return const Color(0xFF4CAF7D);
    case 'rejected':
      return AppColors.alertBorderColor;
    case 'pending':
    default:
      return AppColors.warningTextColor;
  }
}

/// Icon for a status value.
IconData placeStatusIcon(String status) {
  switch (status) {
    case 'approved':
      return Icons.check_circle_rounded;
    case 'rejected':
      return Icons.cancel_rounded;
    case 'pending':
    default:
      return Icons.hourglass_top_rounded;
  }
}

/// True when a request has been reviewed (approved or rejected) — i.e. it
/// carries a notification-worthy outcome for the submitter.
bool isPlaceStatusResolved(String status) =>
    status == 'approved' || status == 'rejected';

/// A small pill showing the status label + icon.
class PlaceStatusChip extends StatelessWidget {
  final String status;
  final double fontSize;

  const PlaceStatusChip({super.key, required this.status, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final color = placeStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(placeStatusIcon(status), size: fontSize + 3, color: color),
          const SizedBox(width: 4),
          Text(
            context.watch<SettingsProvider>().t.placeStatusLabel(status),
            style: GoogleFonts.notoSansKhmer(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

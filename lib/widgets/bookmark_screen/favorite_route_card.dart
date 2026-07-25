import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/favorite_route.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/theme/app_palette.dart';

/// A saved transit route row in the bookmark screen, styled to match
/// [FavoritePlaceCard]: a leading route badge, the origin → destination line,
/// a transfer/leg summary, the saved-at label and an overflow menu.
class FavoriteRouteCard extends StatelessWidget {
  final FavoriteRoute favorite;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const FavoriteRouteCard({
    super.key,
    required this.favorite,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final p = context.palette;
    return Material(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(),
              const SizedBox(width: 12),
              Expanded(child: _details(p, t)),
              _menu(context, t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge() {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.secondaryColor.withAlpha(40),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.directions_bus_rounded,
        color: AppColors.secondaryColor,
        size: 24,
      ),
    );
  }

  Widget _details(AppPalette p, AppTexts t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          favorite.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKhmer(
            color: p.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        _endpointLine(
          p,
          Icons.trip_origin,
          Colors.greenAccent,
          favorite.origin.name,
        ),
        const SizedBox(height: 3),
        _endpointLine(
          p,
          Icons.location_on,
          const Color(0xFFF97316),
          favorite.destination.name,
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(Icons.bookmark, size: 13, color: p.textFaintest),
            const SizedBox(width: 5),
            Text(
              t.savedAgo(favorite.savedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKhmer(
                color: p.textFaint,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _endpointLine(AppPalette p, IconData icon, Color color, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text.isEmpty ? '—' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKhmer(
              color: p.textSecondary,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context, AppTexts t) {
    final p = context.palette;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: p.textFaint, size: 20),
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      tooltip: t.options,
      onSelected: (value) {
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              const Icon(
                Icons.bookmark_remove_outlined,
                size: 18,
                color: AppColors.alertBorderColor,
              ),
              const SizedBox(width: 10),
              Text(
                t.removeFromBookmarks,
                style: GoogleFonts.notoSansKhmer(
                  color: AppColors.alertBorderColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

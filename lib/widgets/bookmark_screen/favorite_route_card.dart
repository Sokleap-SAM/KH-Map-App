import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/favorite_route.dart';
import '../../utils/constants/colors.dart';
import 'favorite_place_card.dart' show kFavSurfaceColor, kFavBorderColor, favoriteSavedLabel;

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
    return Material(
      color: kFavSurfaceColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kFavBorderColor),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _badge(),
              const SizedBox(width: 12),
              Expanded(child: _details()),
              _menu(context),
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

  Widget _details() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          favorite.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        _endpointLine(Icons.trip_origin, Colors.greenAccent, favorite.origin.name),
        const SizedBox(height: 3),
        _endpointLine(Icons.location_on, const Color(0xFFF97316), favorite.destination.name),
        const SizedBox(height: 5),
        Row(
          children: [
            const Icon(Icons.bookmark, size: 13, color: Colors.white38),
            const SizedBox(width: 5),
            Text(
              favoriteSavedLabel(favorite.savedAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white54,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _endpointLine(IconData icon, Color color, String text) {
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
              color: Colors.white70,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      color: const Color(0xFF243456),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      tooltip: 'ជម្រើស',
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
                'លុបចេញពីចំណាំ',
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

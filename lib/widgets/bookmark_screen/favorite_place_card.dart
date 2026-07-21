import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/favorites_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';

/// Surface colour shared by the saved-places cards, banner and sheet.
const Color kFavSurfaceColor = Color(0xFF1A2A4C);
const Color kFavBorderColor = Colors.white12;

/// Turns a raw category slug (`coffee_shop`) into a readable label.
String formatCategoryLabel(String? name) {
  if (name == null || name.trim().isEmpty) return 'ទីកន្លែង';
  return name
      .replaceAll('_', ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// A single saved place, styled after a Google Maps "saved list" row:
/// square thumbnail, name, rating, coordinates/distance and an overflow menu.
class FavoritePlaceCard extends StatelessWidget {
  final FavoritePlace favorite;
  final String? distanceLabel;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onCopy;

  const FavoritePlaceCard({
    super.key,
    required this.favorite,
    required this.onTap,
    required this.onRemove,
    required this.onCopy,
    this.distanceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final color = getColorForCategory(favorite.categoryName);
    final icon = getIconForCategory(favorite.categoryName);

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
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbnail(icon, color),
              const SizedBox(width: 12),
              Expanded(child: _details(context, t, icon, color)),
              _menu(context, t),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(IconData icon, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 78,
        height: 78,
        child: (favorite.photo == null || favorite.photo!.isEmpty)
            ? _iconTile(icon, color)
            : Image.network(
                favorite.photo!,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _iconTile(icon, color),
                errorBuilder: (_, _, _) => _iconTile(icon, color),
              ),
      ),
    );
  }

  Widget _iconTile(IconData icon, Color color) {
    return Container(
      color: color.withAlpha(45),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 30),
    );
  }

  Widget _details(
    BuildContext context,
    AppTexts t,
    IconData icon,
    Color color,
  ) {
    final coords =
        '${favorite.latitude.toStringAsFixed(4)}, '
        '${favorite.longitude.toStringAsFixed(4)}';
    final locationLine =
        distanceLabel == null ? coords : '$coords  ·  $distanceLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          favorite.localizedName(
            context.watch<SettingsProvider>().languageCode,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        _ratingLine(icon, color),
        const SizedBox(height: 5),
        _metaLine(Icons.place_outlined, locationLine),
        const SizedBox(height: 3),
        _metaLine(Icons.bookmark, t.savedAgo(favorite.favoritedAt)),
      ],
    );
  }

  Widget _ratingLine(IconData icon, Color color) {
    final rating = favorite.averageRating;
    final category = formatCategoryLabel(favorite.categoryName);

    return Row(
      children: [
        if (rating != null) ...[
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB400)),
          const SizedBox(width: 3),
          Text(
            rating.toStringAsFixed(1),
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (favorite.ratingCount != null) ...[
            const SizedBox(width: 3),
            Text(
              '(${favorite.ratingCount})',
              style: GoogleFonts.notoSansKhmer(
                color: AppColors.secondaryTextColor,
                fontSize: 12,
              ),
            ),
          ],
          Text(
            '  ·  ',
            style: GoogleFonts.notoSansKhmer(
              color: AppColors.secondaryTextColor,
              fontSize: 12,
            ),
          ),
        ] else
          Icon(icon, size: 14, color: color),
        if (rating == null) const SizedBox(width: 4),
        Flexible(
          child: Text(
            category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKhmer(
              color: AppColors.secondaryTextColor,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metaLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.white38),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white54,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _menu(BuildContext context, AppTexts t) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      color: const Color(0xFF243456),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      tooltip: t.options,
      onSelected: (value) {
        if (value == 'copy') onCopy();
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => [
        _menuItem('copy', Icons.copy_rounded, t.copyLocation, Colors.white),
        _menuItem(
          'remove',
          Icons.bookmark_remove_outlined,
          t.removeFromBookmarks,
          AppColors.alertBorderColor,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    Color color,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.notoSansKhmer(color: color, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

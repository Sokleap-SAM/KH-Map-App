import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/favorites_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import 'favorite_place_card.dart';

/// Result returned from [FavoritePlaceSheet] via [Navigator.pop].
const String kFavSheetRemove = 'remove';

/// A Google-Maps-style detail sheet for one saved place: a non-interactive
/// mini-map preview on top, then the place name, rating, quick actions and
/// an info list. Pops with [kFavSheetRemove] when the user removes the place.
class FavoritePlaceSheet extends StatelessWidget {
  final FavoritePlace favorite;
  final String? distanceLabel;

  const FavoritePlaceSheet({
    super.key,
    required this.favorite,
    this.distanceLabel,
  });

  static const Color _divider = Colors.white12;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    final color = getColorForCategory(favorite.categoryName);
    final icon = getIconForCategory(favorite.categoryName);

    return DraggableScrollableSheet(
      initialChildSize: 0.64,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.primaryColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _dragHandle(),
              _miniMap(color, icon),
              const SizedBox(height: 16),
              _titleBlock(context, t, color, icon),
              const SizedBox(height: 16),
              _actionRow(context, t),
              const SizedBox(height: 8),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: icon,
                iconColor: color,
                primary: formatCategoryLabel(favorite.categoryName),
                label: t.category,
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFFFB400),
                primary: favorite.averageRating != null
                    ? '${favorite.averageRating!.toStringAsFixed(1)}'
                          '  ·  ${t.ratingsCount(favorite.ratingCount ?? 0)}'
                    : t.noRatingsYet,
                label: t.rating,
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.place_outlined,
                primary:
                    '${favorite.latitude.toStringAsFixed(6)}, '
                    '${favorite.longitude.toStringAsFixed(6)}',
                label: distanceLabel == null
                    ? t.coordinates
                    : t.coordinatesFromYou(distanceLabel!),
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.bookmark_outline,
                primary: t.savedAgo(favorite.favoritedAt),
                label: t.bookmarkStatus,
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }

  Widget _dragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 12),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _miniMap(Color color, IconData icon) {
    final point = LatLng(favorite.latitude, favorite.longitude);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 190,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 16,
                  interactionOptions:
                      const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.kh_map_app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: _pin(color, icon),
                      ),
                    ],
                  ),
                ],
              ),
              // Soft scrim so the rounded corners read cleanly on bright tiles.
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pin(Color color, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Icon(Icons.arrow_drop_down, color: color, size: 18),
        ),
      ],
    );
  }

  Widget _titleBlock(
    BuildContext context,
    AppTexts t,
    Color color,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  favorite.localizedName(
                    context.watch<SettingsProvider>().languageCode,
                  ),
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (favorite.averageRating != null) ...[
                      Text(
                        favorite.averageRating!.toStringAsFixed(1),
                        style: GoogleFonts.notoSansKhmer(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _StarRow(rating: favorite.averageRating!),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: GoogleFonts.notoSansKhmer(
                          color: AppColors.secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        formatCategoryLabel(favorite.categoryName),
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansKhmer(
                          color: AppColors.secondaryTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: t.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(BuildContext context, AppTexts t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SheetButton(
            icon: Icons.copy_rounded,
            label: t.copyLocation,
            background: AppColors.secondaryColor,
            foreground: AppColors.primaryColor,
            onTap: () => _copyCoordinates(context, t),
          ),
          const SizedBox(width: 10),
          _SheetButton(
            icon: Icons.bookmark_remove_outlined,
            label: t.remove,
            background: kFavSurfaceColor,
            foreground: AppColors.alertBorderColor,
            onTap: () => Navigator.of(context).pop(kFavSheetRemove),
          ),
        ],
      ),
    );
  }

  void _copyCoordinates(BuildContext context, AppTexts t) {
    final text = '${favorite.latitude}, ${favorite.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          t.copiedLocation(text),
          style: GoogleFonts.notoSansKhmer(fontSize: 13),
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final double rating;
  const _StarRow({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating.round() ? Icons.star_rounded : Icons.star_border_rounded,
          size: 15,
          color: const Color(0xFFFFB400),
        );
      }),
    );
  }
}

class _SheetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _SheetButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKhmer(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String primary;
  final String label;

  const _InfoRow({
    required this.icon,
    required this.primary,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.white54),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: GoogleFonts.notoSansKhmer(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.notoSansKhmer(
                    fontSize: 12,
                    color: AppColors.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

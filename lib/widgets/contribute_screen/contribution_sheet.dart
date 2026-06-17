import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../models/contribution.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../bookmark_screen/favorite_place_card.dart';
import 'contribution_card.dart';

/// Pop values from the contribution sheet.
const String kContribSheetRemove = 'remove';
const String kContribSheetEdit = 'edit';

class ContributionSheet extends StatelessWidget {
  final Contribution contribution;
  final String? distanceLabel;

  const ContributionSheet({
    super.key,
    required this.contribution,
    this.distanceLabel,
  });

  static const Color _divider = Colors.white12;

  @override
  Widget build(BuildContext context) {
    final color = getColorForCategory(contribution.categoryName);
    final icon = getIconForCategory(contribution.categoryName);

    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.4,
      maxChildSize: 0.95,
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
              _titleBlock(context, color, icon),
              const SizedBox(height: 16),
              _actionRow(context),
              const SizedBox(height: 12),
              if (contribution.photos.isNotEmpty) ...[
                _photoCarousel(),
                const SizedBox(height: 12),
              ],
              if (contribution.comment.trim().isNotEmpty) ...[
                _commentBlock(),
                const SizedBox(height: 8),
              ],
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.star_rounded,
                iconColor: const Color(0xFFFFB400),
                primary: contribution.rating > 0
                    ? '${contribution.rating.toStringAsFixed(1)}  ·  '
                          '${_starString(contribution.rating)}'
                    : 'មិនទាន់មានការវាយតម្លៃ',
                label: 'ការវាយតម្លៃរបស់អ្នក',
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: icon,
                iconColor: color,
                primary: formatCategoryLabel(contribution.categoryName),
                label: contribution.isCustomPlace
                    ? 'ប្រភេទ · ទីកន្លែងថ្មីបង្កើតដោយអ្នក'
                    : 'ប្រភេទ',
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.place_outlined,
                primary:
                    '${contribution.latitude.toStringAsFixed(6)}, '
                    '${contribution.longitude.toStringAsFixed(6)}',
                label: distanceLabel == null
                    ? 'កូអរដោនេ'
                    : 'កូអរដោនេ  ·  $distanceLabel ពីអ្នក',
              ),
              const Divider(color: _divider, height: 1, indent: 16, endIndent: 16),
              _InfoRow(
                icon: Icons.edit_outlined,
                primary: contributionAddedLabel(contribution.createdAt),
                label: 'ស្ថានភាពចូលរួម',
              ),
              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }

  String _starString(double rating) {
    final r = rating.round().clamp(0, 5);
    return '★' * r + '☆' * (5 - r);
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
    final point = LatLng(contribution.latitude, contribution.longitude);
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
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
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

  Widget _titleBlock(BuildContext context, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        contribution.placeName,
                        style: GoogleFonts.notoSansKhmer(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (contribution.isCustomPlace) _newBadge(),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      contribution.rating > 0
                          ? contribution.rating.toStringAsFixed(1)
                          : '—',
                      style: GoogleFonts.notoSansKhmer(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _StarRow(rating: contribution.rating),
                    const SizedBox(width: 6),
                    Text(
                      '·',
                      style: GoogleFonts.notoSansKhmer(
                        color: AppColors.secondaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        formatCategoryLabel(contribution.categoryName),
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
            tooltip: 'បិទ',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _newBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.secondaryColor.withAlpha(60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.secondaryColor.withAlpha(120)),
      ),
      child: Text(
        'ថ្មី',
        style: GoogleFonts.notoSansKhmer(
          color: AppColors.secondaryColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SheetButton(
            icon: Icons.edit_outlined,
            label: 'កែសម្រួល',
            background: AppColors.secondaryColor,
            foreground: AppColors.primaryColor,
            onTap: () => Navigator.of(context).pop(kContribSheetEdit),
          ),
          const SizedBox(width: 10),
          _SheetButton(
            icon: Icons.copy_rounded,
            label: 'ចម្លងទីតាំង',
            background: kFavSurfaceColor,
            foreground: Colors.white,
            onTap: () => _copyCoordinates(context),
          ),
          const SizedBox(width: 10),
          _SheetButton(
            icon: Icons.delete_outline_rounded,
            label: 'លុប',
            background: kFavSurfaceColor,
            foreground: AppColors.alertBorderColor,
            onTap: () => Navigator.of(context).pop(kContribSheetRemove),
          ),
        ],
      ),
    );
  }

  Widget _photoCarousel() {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: contribution.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 140,
            height: 110,
            child: contributionPhoto(contribution.photos[i]),
          ),
        ),
      ),
    );
  }

  Widget _commentBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kFavSurfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kFavBorderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.format_quote_rounded,
              size: 18,
              color: Colors.white38,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                contribution.comment,
                style: GoogleFonts.notoSansKhmer(
                  color: Colors.white,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyCoordinates(BuildContext context) {
    final text = '${contribution.latitude}, ${contribution.longitude}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          'បានចម្លងទីតាំង៖ $text',
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
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKhmer(
                      color: foreground,
                      fontSize: 12,
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

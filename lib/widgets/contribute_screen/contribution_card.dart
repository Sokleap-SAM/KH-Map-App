import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/contribution.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../bookmark_screen/favorite_place_card.dart';

/// Khmer "added N days ago" label.
String contributionAddedLabel(DateTime createdAt) {
  final diff = DateTime.now().difference(createdAt);
  if (diff.inDays >= 365) return 'បានបន្ថែម ${diff.inDays ~/ 365} ឆ្នាំមុន';
  if (diff.inDays >= 30) return 'បានបន្ថែម ${diff.inDays ~/ 30} ខែមុន';
  if (diff.inDays >= 7) return 'បានបន្ថែម ${diff.inDays ~/ 7} សប្ដាហ៍មុន';
  if (diff.inDays >= 1) return 'បានបន្ថែម ${diff.inDays} ថ្ងៃមុន';
  if (diff.inHours >= 1) return 'បានបន្ថែម ${diff.inHours} ម៉ោងមុន';
  if (diff.inMinutes >= 1) return 'បានបន្ថែម ${diff.inMinutes} នាទីមុន';
  return 'បានបន្ថែមអម្បាញ់មិញ';
}

/// Renders a single photo path (local file or remote URL) into an Image widget.
Widget contributionPhoto(
  String path, {
  BoxFit fit = BoxFit.cover,
  Widget? fallback,
}) {
  Widget onErr(BuildContext _, Object _, StackTrace? _) =>
      fallback ?? const ColoredBox(color: Colors.black26);
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return Image.network(path, fit: fit, errorBuilder: onErr);
  }
  return Image.file(File(path), fit: fit, errorBuilder: onErr);
}

class ContributionCard extends StatelessWidget {
  final Contribution contribution;
  final String? distanceLabel;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const ContributionCard({
    super.key,
    required this.contribution,
    required this.onTap,
    required this.onRemove,
    required this.onEdit,
    this.distanceLabel,
  });

  @override
  Widget build(BuildContext context) {
    final color = getColorForCategory(contribution.categoryName);
    final icon = getIconForCategory(contribution.categoryName);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _thumbnail(icon, color),
                  const SizedBox(width: 12),
                  Expanded(child: _details(icon, color)),
                  _menu(),
                ],
              ),
              if (contribution.comment.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                _commentLine(),
              ],
              if (contribution.photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                _photoStrip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail(IconData icon, Color color) {
    final preview =
        contribution.photos.isNotEmpty ? contribution.photos.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 78,
        height: 78,
        child: preview == null
            ? _iconTile(icon, color)
            : contributionPhoto(preview, fallback: _iconTile(icon, color)),
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

  Widget _details(IconData icon, Color color) {
    final coords =
        '${contribution.latitude.toStringAsFixed(4)}, '
        '${contribution.longitude.toStringAsFixed(4)}';
    final locationLine =
        distanceLabel == null ? coords : '$coords  ·  $distanceLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                contribution.placeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.notoSansKhmer(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (contribution.isCustomPlace) ...[
              const SizedBox(width: 4),
              _customBadge(),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _ratingLine(icon, color),
        const SizedBox(height: 5),
        _metaLine(Icons.place_outlined, locationLine),
        const SizedBox(height: 3),
        _metaLine(Icons.edit_outlined, contributionAddedLabel(contribution.createdAt)),
      ],
    );
  }

  Widget _customBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.secondaryColor.withAlpha(60),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.secondaryColor.withAlpha(120)),
      ),
      child: Text(
        'ថ្មី',
        style: GoogleFonts.notoSansKhmer(
          color: AppColors.secondaryColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _ratingLine(IconData icon, Color color) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFFFB400)),
        const SizedBox(width: 3),
        Text(
          contribution.rating > 0
              ? contribution.rating.toStringAsFixed(1)
              : '—',
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '  ·  ',
          style: GoogleFonts.notoSansKhmer(
            color: AppColors.secondaryTextColor,
            fontSize: 12,
          ),
        ),
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            formatCategoryLabel(contribution.categoryName),
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

  Widget _commentLine() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote_rounded, size: 16, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              contribution.comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white70,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoStrip() {
    final photos = contribution.photos.take(4).toList();
    final extra = contribution.photos.length - photos.length;
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          for (var i = 0; i < photos.length; i++) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: contributionPhoto(photos[i]),
              ),
            ),
            if (i != photos.length - 1) const SizedBox(width: 6),
          ],
          if (extra > 0) ...[
            const SizedBox(width: 6),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                '+$extra',
                style: GoogleFonts.notoSansKhmer(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      color: const Color(0xFF243456),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      tooltip: 'ជម្រើស',
      onSelected: (value) {
        if (value == 'edit') onEdit();
        if (value == 'remove') onRemove();
      },
      itemBuilder: (_) => [
        _menuItem('edit', Icons.edit_outlined, 'កែសម្រួល', Colors.white),
        _menuItem(
          'remove',
          Icons.delete_outline_rounded,
          'លុបការចូលរួម',
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

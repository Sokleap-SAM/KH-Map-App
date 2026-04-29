import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/constants/colors.dart';

class SearchHistoryItem {
  final String title;
  final String subtitle;
  final bool isSelected;

  const SearchHistoryItem({
    required this.title,
    required this.subtitle,
    this.isSelected = false,
  });
}

class SearchHistoryList extends StatelessWidget {
  final List<SearchHistoryItem> items;
  final ValueChanged<SearchHistoryItem>? onTap;

  const SearchHistoryList({
    super.key,
    required this.items,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A4C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _HistoryRow(
              item: items[i],
              onTap: onTap == null ? null : () => onTap!(items[i]),
            ),
            if (i != items.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Colors.white12,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final SearchHistoryItem item;
  final VoidCallback? onTap;

  const _HistoryRow({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.access_time,
            color: Colors.white70,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKhmer(
                    color: AppColors.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final row = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: content,
    );

    if (!item.isSelected) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: row,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF5C7EBD), width: 1.5),
        ),
        child: row,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';

class SearchQuickCategoryRow extends StatelessWidget {
  const SearchQuickCategoryRow({super.key, required this.onCategorySelected});

  final ValueChanged<String> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _QuickCategory(
          icon: Icons.home_outlined,
          label: t.quickHome,
          query: 'hotel',
          onTap: onCategorySelected,
        ),
        _QuickCategory(
          icon: Icons.work_outline,
          label: t.quickWork,
          query: 'office',
          onTap: onCategorySelected,
        ),
        _QuickCategory(
          icon: Icons.account_balance_outlined,
          label: t.quickSchool,
          query: 'education',
          onTap: onCategorySelected,
        ),
        _QuickCategory(
          icon: Icons.more_horiz,
          label: t.quickOther,
          query: 'restaurant',
          onTap: onCategorySelected,
        ),
      ],
    );
  }
}

class _QuickCategory extends StatelessWidget {
  final IconData icon;
  final String label;
  final String query;
  final ValueChanged<String> onTap;

  const _QuickCategory({
    required this.icon,
    required this.label,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(query),
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF243350),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

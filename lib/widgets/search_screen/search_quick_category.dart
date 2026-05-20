import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SearchQuickCategoryRow extends StatelessWidget {
  const SearchQuickCategoryRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: const [
        _QuickCategory(icon: Icons.home_outlined, label: 'លំនៅឋាន'),
        _QuickCategory(icon: Icons.work_outline, label: 'កន្លែងធ្វើការ'),
        _QuickCategory(icon: Icons.account_balance_outlined, label: 'សាលារៀន'),
        _QuickCategory(icon: Icons.more_horiz, label: 'ផ្សេងៗ'),
      ],
    );
  }
}

class _QuickCategory extends StatelessWidget {
  final IconData icon;
  final String label;

  const _QuickCategory({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }
}

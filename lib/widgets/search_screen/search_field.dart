import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/constants/colors.dart';
import '../../utils/theme/app_palette.dart';

class SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onBack;
  final ValueChanged<String>? onSubmitted;

  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onBack,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.secondaryColor, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.secondaryColor,
              size: 18,
            ),
            splashRadius: 20,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              cursorColor: AppColors.secondaryColor,
              onSubmitted: onSubmitted,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              style: GoogleFonts.notoSansKhmer(
                color: context.palette.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: GoogleFonts.notoSansKhmer(
                  color: context.palette.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

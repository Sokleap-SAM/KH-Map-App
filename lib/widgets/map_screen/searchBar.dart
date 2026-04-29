import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../screens/search_screen.dart';
import '../../utils/constants/colors.dart';

class MapSearchBar extends StatelessWidget {
  const MapSearchBar({super.key});

  void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryColor,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search field
          GestureDetector(
            onTap: () => _openSearch(context),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF243350),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.secondaryColor,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.secondaryColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ស្វែងរកទីកន្លែង . . .',
                      style: GoogleFonts.notoSansKhmer(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Category buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CategoryButton(
                icon: Icons.restaurant,
                label: 'មូលអាហារ',
                color: AppColors.buttonCategoryBlueColor,
              ),
              _CategoryButton(
                icon: Icons.hotel,
                label: 'សណ្ឋាគារ',
                color: AppColors.buttonCategoryBrownColor,
              ),
              _CategoryButton(
                icon: Icons.shopping_cart_outlined,
                label: 'ផ្សារ',
                color: AppColors.buttonCategoryPurpleColor,
              ),
              _CategoryButton(
                icon: Icons.attractions,
                label: 'កន្លែងកម្សាន្ត',
                color: AppColors.buttonCategoryYellowColor,
              ),
              _CategoryButton(
                icon: Icons.local_cafe_outlined,
                label: 'បាងកាហេ',
                color: AppColors.buttonCategoryPinkColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(50),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

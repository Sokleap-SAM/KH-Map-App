import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/place.dart';
import '../../screens/search_screen.dart';
import '../../utils/constants/colors.dart';

/// A category shown under the search bar. Tapping it filters the map to the
/// nearby places whose category name contains any of [keywords].
class MapCategory {
  final String key;
  final IconData icon;
  final String label;
  final Color color;
  final List<String> keywords;

  const MapCategory({
    required this.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.keywords,
  });
}

const List<MapCategory> kMapCategories = [
  MapCategory(
    key: 'restaurant',
    icon: Icons.restaurant,
    label: 'ភោជនីយដ្ឋាន',
    color: AppColors.buttonCategoryBlueColor,
    keywords: ['restaurant', 'food', 'ភោជន'],
  ),
  MapCategory(
    key: 'hotel',
    icon: Icons.hotel,
    label: 'សណ្ឋាគារ',
    color: AppColors.buttonCategoryBrownColor,
    keywords: ['hotel', 'guesthouse', 'lodging', 'សណ្ឋាគារ'],
  ),
  MapCategory(
    key: 'market',
    icon: Icons.shopping_cart_outlined,
    label: 'ផ្សារ',
    color: AppColors.buttonCategoryPurpleColor,
    keywords: ['market', 'shopping', 'mall', 'supermarket', 'ផ្សារ'],
  ),
  MapCategory(
    key: 'entertainment',
    icon: Icons.attractions,
    label: 'កន្លែងកម្សាន្ត',
    color: AppColors.buttonCategoryYellowColor,
    keywords: ['park', 'entertainment', 'attraction', 'amusement', 'កម្សាន្ត'],
  ),
  MapCategory(
    key: 'coffee',
    icon: Icons.local_cafe_outlined,
    label: 'ហាងកាហ្វេ',
    color: AppColors.buttonCategoryPinkColor,
    keywords: ['coffee', 'cafe', 'កាហ្វេ'],
  ),
];

class MapSearchBar extends StatelessWidget {
  final ValueChanged<Place>? onPlaceSelected;

  /// Key of the currently active nearby-category filter, used to highlight
  /// the matching button. Null when no filter is active.
  final String? activeCategory;

  /// Called when a category icon is tapped. The map screen runs the nearby
  /// search and fits the camera to the results.
  final ValueChanged<MapCategory>? onCategorySelected;

  const MapSearchBar({
    super.key,
    this.onPlaceSelected,
    this.activeCategory,
    this.onCategorySelected,
  });

  Future<void> _openSearch(BuildContext context, {String? initialQuery}) async {
    final selected = await Navigator.of(context).push<Place>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialQuery: initialQuery),
      ),
    );
    if (selected != null) {
      onPlaceSelected?.call(selected);
    }
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
          // Category buttons — tap to find that category near you on the map.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final category in kMapCategories)
                _CategoryButton(
                  icon: category.icon,
                  label: category.label,
                  color: category.color,
                  selected: activeCategory == category.key,
                  onTap: () => onCategorySelected?.call(category),
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
  final bool selected;
  final VoidCallback onTap;

  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? color : color.withAlpha(50),
                borderRadius: BorderRadius.circular(10),
                border: selected
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : color,
                size: 22,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white,
                fontSize: 10,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

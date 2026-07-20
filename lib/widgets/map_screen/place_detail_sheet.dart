import 'package:flutter/material.dart';
import 'package:kh_map_app/models/place.dart';
import 'package:kh_map_app/screens/place_reviews_screen.dart';
import 'package:kh_map_app/utils/category_icon.dart';

class PlaceDetailSheet extends StatefulWidget {
  final Place place;
  final bool initialFavorite;
  final ValueChanged<bool>? onFavoriteChanged;
  final VoidCallback? onDirections;
  final VoidCallback? onShare;

  const PlaceDetailSheet({
    super.key,
    required this.place,
    this.initialFavorite = false,
    this.onFavoriteChanged,
    this.onDirections,
    this.onShare,
  });

  @override
  State<PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends State<PlaceDetailSheet> {
  static const _bgColor = Color(0xFF1E1E1E);
  static const _surfaceColor = Color(0xFF2D2D2D);
  static const _dividerColor = Color(0xFF333333);
  static const _accentBlue = Color(0xFF3B82F6);

  final PageController _photoController = PageController();
  late bool _isFavorite;
  int _currentPhoto = 0;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.initialFavorite;
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  void _openReviews() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaceReviewsScreen(place: widget.place),
      ),
    );
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    widget.onFavoriteChanged?.call(_isFavorite);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        content: Text(
          _isFavorite
              ? 'Saved "${widget.place.name}" to favorites'
              : 'Removed "${widget.place.name}" from favorites',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final categoryName = place.category?.name;
    final categoryColor = getColorForCategory(categoryName);
    final categoryIcon = getIconForCategory(categoryName);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: _bgColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              _dragHandle(),
              _photoHeader(place, categoryIcon, categoryColor),
              const SizedBox(height: 16),
              _titleBlock(place, categoryIcon, categoryColor),
              const SizedBox(height: 16),
              _actionRow(),
              const SizedBox(height: 20),
              const Divider(color: _dividerColor, height: 1),
              _InfoRow(
                icon: categoryIcon,
                iconColor: categoryColor,
                primary: _formatCategory(categoryName),
                secondary: 'Category',
              ),
              const Divider(color: _dividerColor, height: 1),
              _InfoRow(
                icon: Icons.star_outline,
                primary: place.averageRating != null
                    ? '${place.averageRating!.toStringAsFixed(1)} '
                          '· ${place.ratingCount ?? 0} ratings'
                    : 'No ratings yet',
                secondary: 'Rating · Tap to read reviews',
                onTap: _openReviews,
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.grey,
                  size: 22,
                ),
              ),
              const Divider(color: _dividerColor, height: 1),
              _InfoRow(
                icon: Icons.location_on_outlined,
                primary:
                    '${place.latitude.toStringAsFixed(6)}, '
                    '${place.longitude.toStringAsFixed(6)}',
                secondary: 'Coordinates',
              ),
              const SizedBox(height: 24),
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
          color: Colors.grey[600],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _photoHeader(Place place, IconData icon, Color color) {
    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: place.photos.isEmpty
              ? _photoFallback(icon, color)
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _photoController,
                      itemCount: place.photos.length,
                      onPageChanged: (i) => setState(() => _currentPhoto = i),
                      itemBuilder: (_, i) => Image.network(
                        place.photos[i],
                        fit: BoxFit.cover,
                        width: double.infinity,
                        loadingBuilder: (_, child, progress) =>
                            progress == null
                            ? child
                            : Container(
                                color: _surfaceColor,
                                alignment: Alignment.center,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                        errorBuilder: (_, _, _) => _photoFallback(icon, color),
                      ),
                    ),
                    if (place.photos.length > 1) _pageIndicator(place.photos.length),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _pageIndicator(int count) {
    return Positioned(
      bottom: 10,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == _currentPhoto;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white54,
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }

  Widget _photoFallback(IconData icon, Color color) {
    return Container(
      color: color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(icon, size: 72, color: color),
    );
  }

  Widget _titleBlock(Place place, IconData icon, Color color) {
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
                  place.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                _metaRow(place, icon, color),
              ],
            ),
          ),
          IconButton(
            tooltip: _isFavorite ? 'Remove from favorites' : 'Save to favorites',
            onPressed: _toggleFavorite,
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite ? Colors.redAccent : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(Place place, IconData icon, Color color) {
    final children = <Widget>[];
    if (place.averageRating != null) {
      children.addAll([
        Text(
          place.averageRating!.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        _StarRow(rating: place.averageRating!),
        if (place.ratingCount != null) ...[
          const SizedBox(width: 6),
          Text(
            '(${place.ratingCount})',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
        const Text('  ·  ', style: TextStyle(color: Colors.grey)),
      ]);
    }
    children.addAll([
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          _formatCategory(place.category?.name),
          style: const TextStyle(color: Colors.grey, fontSize: 13),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
    return Row(children: children);
  }

  Widget _actionRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _ActionChip(
            icon: Icons.directions,
            label: 'Directions',
            background: _accentBlue,
            foreground: Colors.white,
            onTap: widget.onDirections ?? () {},
          ),
          const SizedBox(width: 10),
          _ActionChip(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            label: _isFavorite ? 'Saved' : 'Save',
            background: _surfaceColor,
            foreground: _isFavorite ? Colors.redAccent : Colors.white,
            onTap: _toggleFavorite,
          ),
          const SizedBox(width: 10),
          _ActionChip(
            icon: Icons.share_outlined,
            label: 'Share',
            background: _surfaceColor,
            foreground: Colors.white,
            onTap: widget.onShare ?? () {},
          ),
        ],
      ),
    );
  }

  static String _formatCategory(String? name) {
    if (name == null || name.isEmpty) return 'Place';
    final spaced = name.replaceAll('_', ' ').trim();
    return spaced
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
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
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star : Icons.star_border,
          size: 14,
          color: const Color(0xFFFFB400),
        );
      }),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionChip({
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
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: foreground,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
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
  final String? secondary;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _InfoRow({
    required this.icon,
    required this.primary,
    this.secondary,
    this.iconColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? Colors.grey),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  primary,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
                if (secondary != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondary!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

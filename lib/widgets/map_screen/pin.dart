import 'package:flutter/material.dart';

import '../../utils/theme/app_palette.dart';

class DroppedPin extends StatelessWidget {
  const DroppedPin({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_pin, color: Colors.red, size: 48),
        SizedBox(
          width: 8,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

String extractPinTitle(String displayName) {
  final parts = displayName.split(',');
  if (parts.length >= 2) {
    return '${parts[0].trim()}, ${parts[1].trim()}';
  }
  return parts.first.trim();
}

class PinInfoSheet extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? placeName;
  final String? road;
  final bool isLoading;
  final VoidCallback? onDirections;

  const PinInfoSheet({
    super.key,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.road,
    this.isLoading = false,
    this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DraggableScrollableSheet(
      initialChildSize: 0.35,
      minChildSize: 0.2,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header: title + action buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title & subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            placeName != null && !isLoading
                                ? extractPinTitle(placeName!)
                                : 'Dropped Pin',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (isLoading)
                            Text(
                              'Looking up location...',
                              style: TextStyle(
                                fontSize: 14,
                                color: p.textFaint,
                              ),
                            )
                          else if (road != null)
                            Text(
                              road!,
                              style: TextStyle(
                                fontSize: 14,
                                color: p.textFaint,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Action icons
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.bookmark_border,
                        color: p.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.share_outlined,
                        color: p.textPrimary,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Action buttons row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _ActionChip(
                      icon: Icons.directions,
                      label: 'Directions',
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        Navigator.of(context).pop();
                        onDirections?.call();
                      },
                    ),
                    const SizedBox(width: 10),
                    _ActionChip(
                      icon: Icons.play_arrow,
                      label: 'Start',
                      color: const Color(0xFF3B82F6),
                      onTap: () {
                        Navigator.of(context).pop();
                        onDirections?.call();
                      },
                    ),
                    const SizedBox(width: 10),
                    _ActionChip(
                      icon: Icons.bookmark_border,
                      label: 'Save',
                      color: p.surfaceAlt,
                      foreground: p.textPrimary,
                      onTap: () {},
                    ),
                    const SizedBox(width: 10),
                    _ActionChip(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      color: p.surfaceAlt,
                      foreground: p.textPrimary,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Divider(color: p.divider, height: 1),
              // Coordinate info row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: p.textFaint,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: p.divider, height: 1),
              // Full address
              if (placeName != null && !isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 20,
                        color: p.textFaint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          placeName!,
                          style: TextStyle(
                            fontSize: 14,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (placeName != null && !isLoading)
                Divider(color: p.divider, height: 1),
              // Road info
              if (road != null && !isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: 20,
                        color: p.textFaint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          road!,
                          style: TextStyle(
                            fontSize: 14,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (road != null && !isLoading)
                Divider(color: p.divider, height: 1),
              // Loading indicator
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.textFaint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Looking up location...',
                        style: TextStyle(fontSize: 14, color: p.textFaint),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.foreground = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
          ),
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
    );
  }
}

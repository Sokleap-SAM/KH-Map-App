import 'package:flutter/material.dart';

import '../../utils/constants/colors.dart';

/// Small overlay control that cycles a map "banner" between height presets
/// (60% → 30% → 10%). Tapping calls [onTap]; the label shows the current size.
class MapSizeButton extends StatelessWidget {
  final double fraction;
  final VoidCallback onTap;
  const MapSizeButton({super.key, required this.fraction, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(8),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.height, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Map ${(fraction * 100).round()}%',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/map_provider.dart';
import '../../utils/theme/app_palette.dart';

/// Banner shown at the bottom of the map while the user is in map-pick mode.
/// Reads [MapProvider.isMapPickMode] and calls [MapProvider.cancelMapPick].
class MapPickBanner extends StatelessWidget {
  const MapPickBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isPickMode = context.select<MapProvider, bool>(
      (p) => p.isMapPickMode,
    );
    if (!isPickMode) return const SizedBox.shrink();
    final p = context.palette;

    return Positioned(
      bottom: 120,
      left: 24,
      right: 24,
      child: Material(
        color: p.surface,
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.touch_app, color: p.textPrimary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tap anywhere on the map to pick a location',
                  style: TextStyle(color: p.textPrimary, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => context.read<MapProvider>().cancelMapPick(),
                child: Icon(Icons.close, color: p.textFaint, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

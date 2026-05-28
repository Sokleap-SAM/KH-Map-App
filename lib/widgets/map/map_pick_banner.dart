import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/map_provider.dart';

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

    return Positioned(
      bottom: 120,
      left: 24,
      right: 24,
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.touch_app, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Tap anywhere on the map to pick a location',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => context.read<MapProvider>().cancelMapPick(),
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

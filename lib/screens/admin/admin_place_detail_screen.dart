import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../utils/constants/colors.dart';
import 'admin_place_edit_screen.dart';

/// Read-only detail for a place: photos, id, name, category, location, rating.
/// The Edit action opens the edit screen; pops `true` if anything changed so
/// the list refreshes.
class AdminPlaceDetailScreen extends StatefulWidget {
  final Place place;
  const AdminPlaceDetailScreen({super.key, required this.place});

  @override
  State<AdminPlaceDetailScreen> createState() => _AdminPlaceDetailScreenState();
}

class _AdminPlaceDetailScreenState extends State<AdminPlaceDetailScreen> {
  late Place _place;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _place = widget.place;
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminPlaceEditScreen(existing: _place),
      ),
    );
    if (ok == true) {
      _changed = true;
      // We don't get the updated Place back; signal the list to reload and pop.
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _place;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          title: Text(p.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'កែ (Edit)',
              onPressed: _edit,
            ),
          ],
        ),
        body: ListView(
          children: [
            _photos(p),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _row('ID', p.id),
                  _row('ប្រភេទ (Category)', p.category?.name ?? '—'),
                  _row('ទីតាំង (Location)',
                      '${p.latitude}, ${p.longitude}'),
                  _row('ចំនួនផ្តល់ពិន្ទុ (Rating count)',
                      p.ratingCount?.toString() ?? '0'),
                  _row(
                    'ពិន្ទុមធ្យម (Average rating)',
                    p.averageRating != null
                        ? '${p.averageRating!.toStringAsFixed(1)} / 5'
                        : '—',
                  ),
                  _row('ចំនួនរូបភាព (Photos)', '${p.photos.length}'),
                ],
              ),
            ),
            SizedBox(height: 220, child: _map(p)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _photos(Place p) {
    if (p.photos.isEmpty) {
      return Container(
        height: 160,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Text('មិនមានរូបភាព (No photos)',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: p.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _preview(p.photos[i]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              p.photos[i],
              width: 280,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 280,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _preview(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _map(Place p) {
    final loc = LatLng(p.latitude, p.longitude);
    return FlutterMap(
      options: MapOptions(initialCenter: loc, initialZoom: 15),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: loc,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on, color: Colors.red, size: 40),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';

/// Create or edit a stop (Place). Tap the map to set/move the marker, type a
/// name, save. Pops `true` on success.
///
/// When [existing] is non-null this is edit mode (PATCH /places/:id) and shows
/// the "moving a stop breaks route segments" warning.
class AdminStopEditScreen extends StatefulWidget {
  final Place? existing;
  const AdminStopEditScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AdminStopEditScreen> createState() => _AdminStopEditScreenState();
}

class _AdminStopEditScreenState extends State<AdminStopEditScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _nameCtrl = TextEditingController();
  LatLng? _point;
  bool _saving = false;

  // Existing stops shown as reference so the admin doesn't place duplicates.
  List<Place> _existing = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _point = LatLng(e.latitude, e.longitude);
    }
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    try {
      final places = await AdminService().fetchPlaces();
      if (!mounted) return;
      // Drop the stop being edited — it's drawn as the movable red marker.
      setState(
        () => _existing = places
            .where((p) => p.id != widget.existing?.id)
            .toList(),
      );
    } catch (_) {
      // Reference layer is best-effort; ignore failures.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('សូមបញ្ចូលឈ្មោះ (Name required)')),
      );
      return;
    }
    if (_point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ចុចលើផែនទីដើម្បីកំណត់ទីតាំង (Tap the map)'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final svc = AdminService();
      if (widget.isEdit) {
        await svc.updatePlace(
          widget.existing!.id,
          name: name,
          longitude: _point!.longitude,
          latitude: _point!.latitude,
        );
      } else {
        await svc.createPlace(
          name: name,
          longitude: _point!.longitude,
          latitude: _point!.latitude,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.isEdit ? 'កែចំណត (Edit stop)' : 'បង្កើតចំណត (New stop)',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'ឈ្មោះចំណត (Stop name)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (widget.isEdit)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'ការផ្លាស់ទីចំណតនឹងធ្វើឲ្យបន្ទាត់ផ្លូវដែលប្រើវាខូចមើលឃើញ '
                'រហូតដល់គូរផ្លូវឡើងវិញ។ (Moving this stop will visually break every '
                'route segment that uses it until those routes are redrawn.)',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _point ?? const LatLng(11.5564, 104.9282),
                    initialZoom: 15,
                    onTap: (_, p) => setState(() => _point = p),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'kh_map_app',
                    ),
                    // Existing stops (reference) — grey dots beneath the marker.
                    MarkerLayer(
                      markers: [
                        for (final p in _existing)
                          Marker(
                            point: LatLng(p.latitude, p.longitude),
                            width: 16,
                            height: 16,
                            child: const Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                    if (_point != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _point!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        _point == null
                            ? 'ចុចលើផែនទីដើម្បីដាក់ចំណត (Tap to place)'
                            : '${_point!.latitude.toStringAsFixed(5)}, '
                                  '${_point!.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.isEdit ? 'រក្សាទុក (Save)' : 'បង្កើត (Create)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

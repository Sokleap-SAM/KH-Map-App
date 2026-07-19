import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/place_category.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';

/// Create or edit a place. Pick a category, tap the map to set/move the
/// marker, type a name, save. Pops `true` on success.
class AdminPlaceEditScreen extends StatefulWidget {
  final Place? existing;
  const AdminPlaceEditScreen({super.key, this.existing});

  bool get isEdit => existing != null;

  @override
  State<AdminPlaceEditScreen> createState() => _AdminPlaceEditScreenState();
}

class _AdminPlaceEditScreenState extends State<AdminPlaceEditScreen> {
  final AdminService _service = AdminService();
  final MapController _mapController = MapController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _nameLatinCtrl = TextEditingController();
  LatLng? _point;
  bool _saving = false;

  List<PlaceCategory> _categories = const [];
  String? _categoryId;

  // Newly-picked local photo file paths (uploaded on save).
  final List<String> _photoPaths = [];
  // Existing (remote) photo URLs the admin chose to keep. Removing one here
  // drops it from the place on save.
  List<String> _keptPhotos = [];
  final ImagePicker _picker = ImagePicker();

  // Other places shown as reference so the admin doesn't place duplicates.
  List<Place> _others = const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.nameInKhmer;
      _nameLatinCtrl.text = e.nameInLatin;
      _point = LatLng(e.latitude, e.longitude);
      _categoryId = e.category?.id;
      _keptPhotos = List<String>.from(e.photos);
    }
    _loadCategories();
    _loadOthers();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _service.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        // Default the picker to the first category on create.
        _categoryId ??= cats.isNotEmpty ? cats.first.id : null;
      });
    } catch (_) {
      // Non-fatal; save still validates a category was chosen.
    }
  }

  Future<void> _loadOthers() async {
    try {
      final places = await _service.fetchAllPlaces();
      if (!mounted) return;
      setState(() =>
          _others = places.where((p) => p.id != widget.existing?.id).toList());
    } catch (_) {
      // Reference layer is best-effort.
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nameLatinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final nameLatin = _nameLatinCtrl.text.trim();
    if (name.isEmpty) {
      _snack('សូមបញ្ចូលឈ្មោះជាភាសាខ្មែរ (Khmer name required)');
      return;
    }
    if (nameLatin.isEmpty) {
      _snack('សូមបញ្ចូលឈ្មោះជាអក្សរឡាតាំង (Latin name required)');
      return;
    }
    if (_categoryId == null) {
      _snack('សូមជ្រើសរើសប្រភេទ (Category required)');
      return;
    }
    if (_point == null) {
      _snack('ចុចលើផែនទីដើម្បីកំណត់ទីតាំង (Tap the map)');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.isEdit) {
        await _service.updatePlace(
          widget.existing!.id,
          nameInKhmer: name,
          nameInLatin: nameLatin,
          longitude: _point!.longitude,
          latitude: _point!.latitude,
          categoryId: _categoryId,
          photoPaths: _photoPaths,
          keepPhotoUrls: _keptPhotos,
        );
      } else {
        await _service.createPlaceInCategory(
          nameInKhmer: name,
          nameInLatin: nameLatin,
          longitude: _point!.longitude,
          latitude: _point!.latitude,
          categoryId: _categoryId!,
          photoPaths: _photoPaths,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      _snack('បរាជ័យ: $msg');
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final picked = await _picker.pickMultiImage();
      if (picked.isEmpty || !mounted) return;
      setState(() => _photoPaths.addAll(picked.map((x) => x.path)));
    } catch (e) {
      if (mounted) _snack('រូបភាពបរាជ័យ: $e');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _buildPhotos() {
    final hasNone = _photoPaths.isEmpty && _keptPhotos.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('រូបភាព (Photos)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: _pickPhotos,
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('បន្ថែម'),
              ),
            ],
          ),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Existing (remote) photos — removable.
                for (int i = 0; i < _keptPhotos.length; i++)
                  _thumb(
                    image: NetworkImage(_keptPhotos[i]),
                    onRemove: () => setState(() => _keptPhotos.removeAt(i)),
                  ),
                // Newly-picked local photos — removable.
                for (int i = 0; i < _photoPaths.length; i++)
                  _thumb(
                    image: FileImage(File(_photoPaths[i])),
                    onRemove: () => setState(() => _photoPaths.removeAt(i)),
                  ),
                if (hasNone)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('មិនមានរូបភាព (No photos)',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb({required ImageProvider image, VoidCallback? onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(image),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image(
                image: image,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 80,
                  height: 80,
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showImagePreview(ImageProvider image) {
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
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image,
                    color: Colors.white54,
                    size: 64,
                  ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.isEdit ? 'កែទីកន្លែង (Edit place)' : 'បង្កើតទីកន្លែង (New place)',
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'ឈ្មោះជាភាសាខ្មែរ (Name in Khmer)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _nameLatinCtrl,
              decoration: const InputDecoration(
                labelText: 'ឈ្មោះជាអក្សរឡាតាំង (Name in Latin)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'ប្រភេទ (Category)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in _categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ),
          _buildPhotos(),
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
                    // Other places (reference) — grey dots beneath the marker.
                    MarkerLayer(
                      markers: [
                        for (final p in _others)
                          Marker(
                            point: LatLng(p.latitude, p.longitude),
                            width: 16,
                            height: 16,
                            child: const Icon(Icons.circle,
                                size: 10, color: Colors.grey),
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
                            child: const Icon(Icons.location_on,
                                color: Colors.red, size: 40),
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
                            ? 'ចុចលើផែនទីដើម្បីដាក់ទីតាំង (Tap to place)'
                            : '${_point!.latitude}, ${_point!.longitude}',
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
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    widget.isEdit ? 'រក្សាទុក (Save)' : 'បង្កើត (Create)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }
}

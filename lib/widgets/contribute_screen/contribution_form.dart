import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/contribution.dart';
import '../../models/place.dart';
import '../../models/place_category.dart';
import '../../providers/map_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/contribution_service.dart';
import '../../utils/constants/text_strings.dart';
import '../../services/place_service.dart';
import '../../utils/category_icon.dart';
import '../../utils/constants/colors.dart';
import '../bookmark_screen/favorite_place_card.dart';
import 'contribution_card.dart';

/// Bottom-sheet form for creating or editing a [Contribution].
///
/// Pops with the persisted [Contribution] on save, or null on cancel.
class ContributionForm extends StatefulWidget {
  final ContributionService service;
  final Contribution? initial;

  const ContributionForm({super.key, required this.service, this.initial});

  @override
  State<ContributionForm> createState() => _ContributionFormState();
}

class _ContributionFormState extends State<ContributionForm> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // Form state.
  bool _useExistingPlace = true;
  Place? _selectedPlace;
  final TextEditingController _placeNameCtrl = TextEditingController();
  final TextEditingController _placeNameLatinCtrl = TextEditingController();
  String _categoryName = 'restaurant';
  LatLng? _customLocation;

  double _rating = 0;
  final TextEditingController _commentCtrl = TextEditingController();
  final List<String> _photos = []; // local paths (already persisted)

  bool _saving = false;
  bool _pickingPhoto = false;
  String? _error;

  List<PlaceCategory> _categories = const [];

  static const List<String> _fallbackCategories = [
    'restaurant',
    'cafe',
    'hotel',
    'shopping',
    'park',
    'hospital',
    'pharmacy',
    'bank',
    'gas_station',
    'education',
    'gym',
    'bus_stop',
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    final initial = widget.initial;
    if (initial != null) {
      _useExistingPlace = !initial.isCustomPlace;
      _placeNameCtrl.text = initial.placeNameKhmer;
      _placeNameLatinCtrl.text = initial.placeNameLatin;
      _categoryName = initial.categoryName;
      _customLocation = LatLng(initial.latitude, initial.longitude);
      _rating = initial.rating;
      _commentCtrl.text = initial.comment;
      _photos.addAll(initial.photos);

      if (!initial.isCustomPlace && initial.placeId != null) {
        // Try to bind to a real Place once the provider data is available.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final places = context.read<MapProvider>().places;
          final match = places.where((p) => p.id == initial.placeId);
          if (match.isNotEmpty) setState(() => _selectedPlace = match.first);
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await PlaceService().fetchCategories();
      if (!mounted) return;
      setState(() => _categories = cats);
    } catch (_) {/* keep fallback */}
  }

  @override
  void dispose() {
    _placeNameCtrl.dispose();
    _placeNameLatinCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ─── Actions ──────────────────────────────────────────────────────────────

  Future<void> _pickPhotos() async {
    if (_pickingPhoto) return;
    setState(() => _pickingPhoto = true);
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 80);
      if (picked.isEmpty) return;
      for (final file in picked) {
        final stored = await widget.service.persistPhoto(file.path);
        if (!mounted) return;
        setState(() => _photos.add(stored));
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = context.read<SettingsProvider>().t.couldNotPickImage,
      );
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
  }

  Future<void> _useCurrentLocation() async {
    final pos = context.read<MapProvider>().currentPosition;
    if (pos == null) {
      _showError(context.read<SettingsProvider>().t.locationUnknownYet);
      return;
    }
    setState(() => _customLocation = pos);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg, style: GoogleFonts.notoSansKhmer(fontSize: 13)),
      ),
    );
  }

  Future<void> _save() async {
    final t = context.read<SettingsProvider>().t;
    if (!_formKey.currentState!.validate()) return;
    if (_rating <= 0) {
      _showError(t.pleaseProvideRating);
      return;
    }
    if (_useExistingPlace && _selectedPlace == null) {
      _showError(t.pleaseSelectPlace);
      return;
    }
    if (!_useExistingPlace && _customLocation == null) {
      _showError(t.pleaseSetLocation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final isEdit = widget.initial != null;
    final id = widget.initial?.id ??
        DateTime.now().microsecondsSinceEpoch.toString();

    final contribution = _useExistingPlace
        ? Contribution.forPlace(
            id: id,
            place: _selectedPlace!,
            rating: _rating,
            comment: _commentCtrl.text.trim(),
            photos: List.of(_photos),
            createdAt: widget.initial?.createdAt,
          )
        : Contribution(
            id: id,
            placeNameKhmer: _placeNameCtrl.text.trim(),
            placeNameLatin: _placeNameLatinCtrl.text.trim(),
            categoryName: _categoryName,
            latitude: _customLocation!.latitude,
            longitude: _customLocation!.longitude,
            rating: _rating,
            comment: _commentCtrl.text.trim(),
            photos: List.of(_photos),
            isCustomPlace: true,
            createdAt: widget.initial?.createdAt ?? DateTime.now(),
          );

    try {
      if (isEdit) {
        await widget.service.update(contribution);
      } else {
        await widget.service.add(contribution);
      }
      if (!mounted) return;
      Navigator.of(context).pop(contribution);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = t.saveFailedTryAgain;
      });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final t = context.watch<SettingsProvider>().t;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.primaryColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _handle(),
                const SizedBox(height: 4),
                _title(t),
                const SizedBox(height: 18),
                _placeModeToggle(t),
                const SizedBox(height: 14),
                if (_useExistingPlace) _existingPlacePicker(t)
                else _customPlaceFields(t),
                const SizedBox(height: 18),
                _sectionLabel(t.rating, Icons.star_rounded),
                const SizedBox(height: 8),
                _ratingPicker(),
                const SizedBox(height: 18),
                _sectionLabel(t.comments, Icons.chat_bubble_outline_rounded),
                const SizedBox(height: 8),
                _commentField(t),
                const SizedBox(height: 18),
                _sectionLabel(
                  t.photosCount(_photos.length),
                  Icons.photo_library_outlined,
                ),
                const SizedBox(height: 8),
                _photoGrid(t),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: GoogleFonts.notoSansKhmer(
                      color: AppColors.alertBorderColor,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _saveButton(t),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _title(AppTexts t) {
    final isEdit = widget.initial != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            isEdit ? t.editContribution : t.newContribution,
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: t.close,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.secondaryColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _placeModeToggle(AppTexts t) {
    return Container(
      decoration: BoxDecoration(
        color: kFavSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kFavBorderColor),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _modeTab(
            label: t.rateTab,
            icon: Icons.place_outlined,
            selected: _useExistingPlace,
            onTap: () => setState(() => _useExistingPlace = true),
          ),
          _modeTab(
            label: t.createNewTab,
            icon: Icons.add_location_alt_outlined,
            selected: !_useExistingPlace,
            onTap: () => setState(() => _useExistingPlace = false),
          ),
        ],
      ),
    );
  }

  Widget _modeTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primaryColor : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.notoSansKhmer(
                  color: selected ? AppColors.primaryColor : Colors.white70,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Existing place mode ──────────────────────────────────────────────────

  Widget _existingPlacePicker(AppTexts t) {
    final places = context.watch<MapProvider>().places;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openPlacePicker(places),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: kFavSurfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kFavBorderColor),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedPlace == null
                      ? Icons.search_rounded
                      : getIconForCategory(_selectedPlace!.category?.name),
                  color: _selectedPlace == null
                      ? Colors.white54
                      : getColorForCategory(_selectedPlace!.category?.name),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedPlace?.localizedName(
                              context.watch<SettingsProvider>().languageCode,
                            ) ??
                            t.selectPlace,
                        style: GoogleFonts.notoSansKhmer(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (_selectedPlace != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatCategoryLabel(_selectedPlace!.category?.name),
                          style: GoogleFonts.notoSansKhmer(
                            color: AppColors.secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openPlacePicker(List<Place> places) async {
    final picked = await showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.primaryColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _PlacePickerSheet(places: places),
    );
    if (picked != null) setState(() => _selectedPlace = picked);
  }

  // ─── Custom place mode ────────────────────────────────────────────────────

  Widget _customPlaceFields(AppTexts t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _textField(
          controller: _placeNameCtrl,
          label: t.nameInKhmerLabel,
          hint: t.nameKhmerHint,
          validator: (v) {
            if (_useExistingPlace) return null;
            if (v == null || v.trim().isEmpty) return t.pleaseEnterName;
            return null;
          },
        ),
        const SizedBox(height: 12),
        _textField(
          controller: _placeNameLatinCtrl,
          label: t.nameInLatinLabel,
          hint: 'e.g. Kaffe Sre Khmer',
          validator: (v) {
            if (_useExistingPlace) return null;
            if (v == null || v.trim().isEmpty) return t.pleaseEnterLatinName;
            return null;
          },
        ),
        const SizedBox(height: 12),
        _categoryDropdown(),
        const SizedBox(height: 12),
        _locationRow(t),
      ],
    );
  }

  Widget _categoryDropdown() {
    final names = _categories.isNotEmpty
        ? _categories.map((c) => c.name).toList()
        : _fallbackCategories;
    final values = {..._fallbackCategories, ...names}.toList();
    if (!values.contains(_categoryName)) values.insert(0, _categoryName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: kFavSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kFavBorderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _categoryName,
          isExpanded: true,
          dropdownColor: const Color(0xFF243456),
          iconEnabledColor: Colors.white54,
          style: GoogleFonts.notoSansKhmer(color: Colors.white, fontSize: 14),
          items: [
            for (final name in values)
              DropdownMenuItem<String>(
                value: name,
                child: Row(
                  children: [
                    Icon(
                      getIconForCategory(name),
                      color: getColorForCategory(name),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formatCategoryLabel(name),
                      style: GoogleFonts.notoSansKhmer(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _categoryName = v);
          },
        ),
      ),
    );
  }

  Widget _locationRow(AppTexts t) {
    final loc = _customLocation;
    final label = loc == null
        ? t.noLocationYet
        : '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kFavSurfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kFavBorderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.locationLabel,
                  style: GoogleFonts.notoSansKhmer(
                    color: AppColors.secondaryTextColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _useCurrentLocation,
            icon: const Icon(Icons.my_location_rounded, size: 16),
            label: Text(
              t.currentShort,
              style: GoogleFonts.notoSansKhmer(fontSize: 12),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Rating / Comment / Photos ────────────────────────────────────────────

  Widget _ratingPicker() {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => setState(() => _rating = i.toDouble()),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                i <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                size: 34,
                color: i <= _rating
                    ? const Color(0xFFFFB400)
                    : Colors.white38,
              ),
            ),
          ),
        const SizedBox(width: 10),
        Text(
          _rating > 0 ? _rating.toStringAsFixed(1) : '—',
          style: GoogleFonts.notoSansKhmer(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _commentField(AppTexts t) {
    return _textField(
      controller: _commentCtrl,
      label: t.commentFieldLabel,
      hint: t.commentFieldHint,
      maxLines: 4,
    );
  }

  Widget _photoGrid(AppTexts t) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _photos.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 78,
                  height: 78,
                  child: contributionPhoto(_photos[i]),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () => _removePhoto(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        _addPhotoTile(t),
      ],
    );
  }

  Widget _addPhotoTile(AppTexts t) {
    return InkWell(
      onTap: _pickPhotos,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: kFavSurfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.secondaryColor.withAlpha(120),
            style: BorderStyle.solid,
          ),
        ),
        alignment: Alignment.center,
        child: _pickingPhoto
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.secondaryColor,
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    color: AppColors.secondaryColor,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.add,
                    style: GoogleFonts.notoSansKhmer(
                      color: AppColors.secondaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.notoSansKhmer(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.notoSansKhmer(
          color: AppColors.secondaryTextColor,
          fontSize: 13,
        ),
        hintStyle: GoogleFonts.notoSansKhmer(
          color: Colors.white38,
          fontSize: 13,
        ),
        filled: true,
        fillColor: kFavSurfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.secondaryColor),
        ),
      ),
    );
  }

  Widget _saveButton(AppTexts t) {
    return FilledButton(
      onPressed: _saving ? null : _save,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: AppColors.primaryColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      child: _saving
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primaryColor,
              ),
            )
          : Text(
              widget.initial == null ? t.save : t.update,
              style: GoogleFonts.notoSansKhmer(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

class _PlacePickerSheet extends StatefulWidget {
  final List<Place> places;
  const _PlacePickerSheet({required this.places});

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<SettingsProvider>().languageCode;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.places
        : widget.places.where((p) {
            return p.nameInKhmer.toLowerCase().contains(q) ||
                p.nameInLatin.toLowerCase().contains(q) ||
                (p.category?.name.toLowerCase().contains(q) ?? false);
          }).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        context.watch<SettingsProvider>().t.searchPlaceHint,
                    hintStyle: GoogleFonts.notoSansKhmer(
                      color: Colors.white38,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white54,
                    ),
                    filled: true,
                    fillColor: kFavSurfaceColor,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.secondaryColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          context.watch<SettingsProvider>().t.placeNotFound,
                          style: GoogleFonts.notoSansKhmer(
                            color: Colors.white54,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        separatorBuilder: (_, _) => const Divider(
                          color: Colors.white12,
                          height: 1,
                        ),
                        itemBuilder: (_, i) {
                          final p = visible[i];
                          final color = getColorForCategory(p.category?.name);
                          final icon = getIconForCategory(p.category?.name);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withAlpha(60),
                              child: Icon(icon, color: color),
                            ),
                            title: Text(
                              p.localizedName(lang),
                              style: GoogleFonts.notoSansKhmer(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              formatCategoryLabel(p.category?.name),
                              style: GoogleFonts.notoSansKhmer(
                                color: AppColors.secondaryTextColor,
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

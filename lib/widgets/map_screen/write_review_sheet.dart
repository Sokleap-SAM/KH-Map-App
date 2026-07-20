import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/place.dart';
import '../../services/place_service.dart';

/// Bottom-sheet form that lets a logged-in user rate a place: a 1–5 star score,
/// an optional comment, and optional photos. Submits to the backend via
/// [PlaceService.submitRating] and pops with `true` on success so the caller
/// can refresh its review list.
class WriteReviewSheet extends StatefulWidget {
  final Place place;

  const WriteReviewSheet({super.key, required this.place});

  @override
  State<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<WriteReviewSheet> {
  static const _bgColor = Color(0xFF1E1E1E);
  static const _surfaceColor = Color(0xFF2D2D2D);
  static const _accentBlue = Color(0xFF3B82F6);
  static const _starColor = Color(0xFFFFB400);
  static const _tokenKey = 'access_token';

  final ImagePicker _picker = ImagePicker();
  final PlaceService _service = PlaceService();
  final TextEditingController _commentCtrl = TextEditingController();

  int _score = 0;
  final List<String> _photos = []; // local file paths
  bool _submitting = false;
  bool _picking = false;
  String? _error;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    return (token == null || token.isEmpty) ? null : token;
  }

  Future<void> _pickPhotos() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 80);
      if (picked.isEmpty) return;
      if (!mounted) return;
      setState(() => _photos.addAll(picked.map((f) => f.path)));
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not pick photos');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  Future<void> _submit() async {
    if (_score <= 0) {
      setState(() => _error = 'Please pick a star rating first');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final token = await _token();
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Please log in to write a review';
      });
      return;
    }

    try {
      await _service.submitRating(
        placeId: widget.place.id,
        score: _score,
        comment: _commentCtrl.text,
        photoPaths: List.of(_photos),
        token: token,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit review — please try again';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _bgColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _handle(),
                const SizedBox(height: 8),
                _header(),
                const SizedBox(height: 18),
                const Text(
                  'Your rating',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _starPicker(),
                const SizedBox(height: 18),
                const Text(
                  'Comment',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _commentField(),
                const SizedBox(height: 18),
                Text(
                  'Photos (${_photos.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _photoGrid(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFEF8181),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _submitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[600],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Write a review',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.place.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _starPicker() {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => setState(() => _score = i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                i <= _score ? Icons.star_rounded : Icons.star_border_rounded,
                size: 38,
                color: i <= _score ? _starColor : Colors.white38,
              ),
            ),
          ),
        const SizedBox(width: 8),
        Text(
          _score > 0 ? '$_score.0' : '—',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _commentField() {
    return TextField(
      controller: _commentCtrl,
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Share details of your experience at this place…',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true,
        fillColor: _surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accentBlue),
        ),
      ),
    );
  }

  Widget _photoGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < _photos.length; i++)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(_photos[i]),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 80,
                    height: 80,
                    color: _surfaceColor,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.white30),
                  ),
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
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
        _addPhotoTile(),
      ],
    );
  }

  Widget _addPhotoTile() {
    return InkWell(
      onTap: _pickPhotos,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _accentBlue.withValues(alpha: 0.5)),
        ),
        alignment: Alignment.center,
        child: _picking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accentBlue,
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      color: _accentBlue, size: 22),
                  SizedBox(height: 4),
                  Text(
                    'Add',
                    style: TextStyle(
                      color: _accentBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _submitting ? null : _submit,
        style: FilledButton.styleFrom(
          backgroundColor: _accentBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Submit review',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}

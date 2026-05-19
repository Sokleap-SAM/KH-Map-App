import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/place.dart';
import '../../utils/constants/colors.dart';

class SearchResultsList extends StatelessWidget {
  final List<Place> results;
  final String query;
  final ValueChanged<Place> onTap;

  const SearchResultsList({
    super.key,
    required this.results,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Text(
            'រកមិនឃើញលទ្ធផលសម្រាប់ "$query"',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKhmer(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A4C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < results.length; i++) ...[
            _ResultRow(
              place: results[i],
              query: query,
              onTap: () => onTap(results[i]),
            ),
            if (i != results.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Colors.white12,
                indent: 16,
                endIndent: 16,
              ),
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final Place place;
  final String query;
  final VoidCallback onTap;

  const _ResultRow({
    required this.place,
    required this.query,
    required this.onTap,
  });

  bool get _isBusStop {
    final name = place.category?.name.toLowerCase() ?? '';
    return name.contains('bus') || name.contains('stop');
  }

  IconData get _icon {
    if (_isBusStop) return Icons.directions_bus_outlined;
    final name = place.category?.name.toLowerCase() ?? '';
    if (name.contains('restaurant') || name.contains('food')) {
      return Icons.restaurant;
    }
    if (name.contains('hotel')) return Icons.hotel;
    if (name.contains('market') || name.contains('shop')) {
      return Icons.shopping_cart_outlined;
    }
    if (name.contains('cafe') || name.contains('coffee')) {
      return Icons.local_cafe_outlined;
    }
    if (name.contains('school') || name.contains('university')) {
      return Icons.account_balance_outlined;
    }
    return Icons.place_outlined;
  }

  Color get _iconColor =>
      _isBusStop ? AppColors.buttonCategoryBlueColor : AppColors.secondaryColor;

  @override
  Widget build(BuildContext context) {
    final categoryLabel = place.category?.name ?? 'Place';
    final coords =
        '${place.latitude.toStringAsFixed(4)}, ${place.longitude.toStringAsFixed(4)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _iconColor.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_icon, color: _iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HighlightedText(text: place.name, query: query),
                  const SizedBox(height: 2),
                  Text(
                    '$categoryLabel  ·  $coords',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKhmer(
                      color: AppColors.secondaryTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.north_west,
              color: Colors.white38,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    final baseStyle = GoogleFonts.notoSansKhmer(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    );

    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    final span = _highlightSpan(text, query, baseStyle);
    if (span == null) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: span,
    );
  }

  // Locate the query inside text while ignoring case, zero-width marks,
  // and whitespace differences. Returns a TextSpan with the matched
  // segment styled, or null if no match exists in the original text.
  static final RegExp _zeroWidth = RegExp('[​‌‍﻿]');

  TextSpan? _highlightSpan(String text, String query, TextStyle baseStyle) {
    final normalizedText = text.replaceAll(_zeroWidth, '').toLowerCase();
    final normalizedQuery = query.replaceAll(_zeroWidth, '').toLowerCase();
    if (normalizedQuery.isEmpty) return null;

    final matchIndex = normalizedText.indexOf(normalizedQuery);
    if (matchIndex < 0) return null;

    // Map the normalized index back to the original string by counting
    // characters and skipping zero-width marks.
    int origStart = -1;
    int origEnd = -1;
    int normCount = 0;
    for (int i = 0; i < text.length; i++) {
      if (normCount == matchIndex && origStart < 0) origStart = i;
      if (normCount == matchIndex + normalizedQuery.length) {
        origEnd = i;
        break;
      }
      if (!_zeroWidth.hasMatch(text[i])) {
        normCount++;
      }
    }
    if (origStart < 0) return null;
    if (origEnd < 0) origEnd = text.length;

    final before = text.substring(0, origStart);
    final match = text.substring(origStart, origEnd);
    final after = text.substring(origEnd);

    return TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: before),
        TextSpan(
          text: match,
          style: baseStyle.copyWith(color: AppColors.secondaryColor),
        ),
        TextSpan(text: after),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/place.dart';
import '../models/place_category.dart';
import '../services/place_service.dart';
import '../services/search_history_service.dart';
import '../utils/constants/colors.dart';
import '../widgets/search_screen/search_field.dart';
import '../widgets/search_screen/search_history_list.dart';
import '../widgets/search_screen/search_quick_category.dart';
import '../widgets/search_screen/search_results_list.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final PlaceService _placeService = PlaceService();
  final SearchHistoryService _historyService = SearchHistoryService();

  List<Place> _allPlaces = [];
  List<Place> _results = [];
  List<SearchHistoryEntry> _history = [];
  String _query = '';
  bool _isLoading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: initial.length),
      );
      _query = initial;
    }
    _loadPlaces();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final entries = await _historyService.load();
    if (!mounted) return;
    setState(() => _history = entries);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final places = await _placeService.fetchPlaces();
      if (!mounted) return;
      setState(() {
        _allPlaces = places;
        _isLoading = false;
        _results = _filter(_query);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'មិនអាចទាញយកទីកន្លែងបានទេ';
        _isLoading = false;
      });
    }
  }

  void _onQueryChanged() {
    final value = _controller.text;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _results = _filter(value);
      });
    });
  }

  List<Place> _filter(String rawQuery) {
    final query = _normalize(rawQuery);
    if (query.isEmpty) return const [];

    final queryTokens = query.split(' ').where((t) => t.isNotEmpty).toList();

    final scored = <_ScoredPlace>[];
    for (final place in _allPlaces) {
      final name = _normalize(place.name);
      final categoryName = _normalize(place.category?.name ?? '');

      int score;
      if (name == query) {
        score = 0;
      } else if (name.startsWith(query)) {
        score = 1;
      } else if (name.contains(query)) {
        score = 2;
      } else if (queryTokens.length > 1 &&
          queryTokens.every((t) => name.contains(t))) {
        score = 3;
      } else if (categoryName.contains(query)) {
        score = 4;
      } else {
        continue;
      }
      scored.add(_ScoredPlace(place, score));
    }

    scored.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      return a.place.name.toLowerCase().compareTo(b.place.name.toLowerCase());
    });

    return scored.take(50).map((s) => s.place).toList(growable: false);
  }

  // Normalize text so Khmer and Latin queries match consistently:
  // strip zero-width marks Khmer text often contains (ZWSP, ZWNJ, ZWJ, BOM),
  // lowercase Latin characters, and collapse whitespace.
  static final RegExp _zeroWidth = RegExp('[​‌‍﻿]');
  static final RegExp _whitespace = RegExp(r'\s+');

  static String _normalize(String input) {
    return input
        .replaceAll(_zeroWidth, '')
        .toLowerCase()
        .replaceAll(_whitespace, ' ')
        .trim();
  }

  void _onQuickCategorySelected(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
  }

  Future<void> _onResultTap(Place place) async {
    final updated = await _historyService.add(place);
    if (!mounted) return;
    setState(() => _history = updated);
    Navigator.of(context).pop(place);
  }

  Future<void> _onHistoryTap(SearchHistoryEntry entry) async {
    final place = _allPlaces.firstWhere(
      (p) => p.id == entry.id,
      orElse: () => Place(
        id: entry.id,
        // History only stores a single display name; reuse it for both.
        nameInKhmer: entry.name,
        nameInLatin: entry.name,
        category: PlaceCategory(id: '', name: entry.categoryName),
        longitude: entry.longitude,
        latitude: entry.latitude,
        photos: const [],
      ),
    );
    await _onResultTap(place);
  }

  Future<void> _onHistoryDismiss(SearchHistoryEntry entry) async {
    setState(() {
      _history = List.of(_history)..removeWhere((e) => e.id == entry.id);
    });
    await _historyService.remove(entry.id);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.primaryColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
              child: SearchField(
                controller: _controller,
                hint: 'ស្វែងរកនៅទីនេះ',
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            if (!hasQuery) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SearchQuickCategoryRow(
                  onCategorySelected: _onQuickCategorySelected,
                ),
              ),
              const Divider(
                color: Colors.white12,
                thickness: 1,
                height: 24,
                indent: 16,
                endIndent: 16,
              ),
            ],
            Expanded(child: _buildBody(hasQuery)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool hasQuery) {
    if (_isLoading && _allPlaces.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.secondaryColor),
      );
    }

    if (_error != null && _allPlaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadPlaces,
              child: Text(
                'ព្យាយាមម្តងទៀត',
                style: GoogleFonts.notoSansKhmer(
                  color: AppColors.secondaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!hasQuery) {
      if (_history.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: Text(
              'ចាប់ផ្តើមវាយដើម្បីស្វែងរកទីកន្លែង ឬចំណតឡានក្រុង',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'ប្រវត្តិស្វែងរក',
                style: GoogleFonts.notoSansKhmer(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SearchHistoryList(
              items: _history,
              onTap: _onHistoryTap,
              onDismiss: _onHistoryDismiss,
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              _results.isEmpty
                  ? 'លទ្ធផល'
                  : 'លទ្ធផល (${_results.length})',
              style: GoogleFonts.notoSansKhmer(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SearchResultsList(
            results: _results,
            query: _query.trim(),
            onTap: _onResultTap,
          ),
        ],
      ),
    );
  }
}

class _ScoredPlace {
  final Place place;
  final int score;
  const _ScoredPlace(this.place, this.score);
}

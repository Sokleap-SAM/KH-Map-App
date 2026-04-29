import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/constants/colors.dart';
import '../widgets/search_screen/search_field.dart';
import '../widgets/search_screen/search_quick_category.dart';
import '../widgets/search_screen/search_history_list.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();

  static const List<SearchHistoryItem> _historyItems = [
    SearchHistoryItem(
      title: 'Institute of Technology of Camb...',
      subtitle: 'Building A, Russian Federation Blvd (110)...',
    ),
    SearchHistoryItem(
      title: 'Toto by Chi Chi ~ coffee, matcha...',
      subtitle: 'Mao Tse Toung Blvd (245), Phnom Pen...',
    ),
    SearchHistoryItem(
      title: 'Institute of Foreign Languages ...',
      subtitle: 'Russian Federation Blvd (110), Phnom Pe...',
      isSelected: true,
    ),
    SearchHistoryItem(
      title: 'Royal University of Phnom Penh',
      subtitle: 'Russian Federation Blvd (110), Phnom Pe...',
    ),
    SearchHistoryItem(
      title: 'KOI The REACHTHEANY',
      subtitle: 'N.83 St 118, Phnom Penh',
    ),
    SearchHistoryItem(
      title: 'AEON Mall Phnom Penh',
      subtitle: '132 Samdach Sothearos Blvd (3), Phnom...',
    ),
    SearchHistoryItem(
      title: 'AEON Mall Sen Sok',
      subtitle: 'St No. 1003, Phnom Penh',
    ),
    SearchHistoryItem(
      title: 'AEON Mall Mean Chey',
      subtitle: 'Samdach Hun Sen Blvd, Phnom Penh...',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SearchQuickCategoryRow(),
            ),
            const Divider(
              color: Colors.white12,
              thickness: 1,
              height: 24,
              indent: 16,
              endIndent: 16,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ប្រវត្តិនៃការស្វែងរក',
                  style: GoogleFonts.notoSansKhmer(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    SearchHistoryList(items: _historyItems),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        'ប្រវត្តិនៃការស្វែងរកបន្ថែមទៀត',
                        style: GoogleFonts.notoSansKhmer(
                          color: AppColors.secondaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

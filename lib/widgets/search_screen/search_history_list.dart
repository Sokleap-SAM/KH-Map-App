import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/search_history_service.dart';
import '../../utils/constants/colors.dart';

class SearchHistoryList extends StatefulWidget {
  final List<SearchHistoryEntry> items;
  final ValueChanged<SearchHistoryEntry>? onTap;
  final ValueChanged<SearchHistoryEntry>? onDismiss;
  final int initialVisible;

  const SearchHistoryList({
    super.key,
    required this.items,
    this.onTap,
    this.onDismiss,
    this.initialVisible = 5,
  });

  @override
  State<SearchHistoryList> createState() => _SearchHistoryListState();
}

class _SearchHistoryListState extends State<SearchHistoryList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final t = context.watch<SettingsProvider>().t;
    final showAll =
        _expanded || widget.items.length <= widget.initialVisible;
    final visible = showAll
        ? widget.items
        : widget.items.take(widget.initialVisible).toList();
    final hiddenCount = widget.items.length - visible.length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A4C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            _DismissibleHistoryRow(
              entry: visible[i],
              onTap: widget.onTap == null
                  ? null
                  : () => widget.onTap!(visible[i]),
              onDismissed: () => widget.onDismiss?.call(visible[i]),
            ),
            if (i != visible.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Colors.white12,
                indent: 16,
                endIndent: 16,
              ),
          ],
          if (widget.items.length > widget.initialVisible) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: Colors.white12,
              indent: 16,
              endIndent: 16,
            ),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded ? t.showLess : t.showMore(hiddenCount),
                      style: GoogleFonts.notoSansKhmer(
                        color: AppColors.secondaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.secondaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DismissibleHistoryRow extends StatelessWidget {
  final SearchHistoryEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onDismissed;

  const _DismissibleHistoryRow({
    required this.entry,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('history_${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Colors.red.withAlpha(180),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 24,
        ),
      ),
      onDismissed: (_) => onDismissed(),
      child: _HistoryRow(entry: entry, onTap: onTap),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final SearchHistoryEntry entry;
  final VoidCallback? onTap;

  const _HistoryRow({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A2A4C),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.access_time,
                color: Colors.white70,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.localizedName(
                        context.watch<SettingsProvider>().languageCode,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKhmer(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.categoryName,
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
      ),
    );
  }
}

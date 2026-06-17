import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/route_plan.dart';
import '../../providers/map_provider.dart';

// Snap stops: collapsed (header only) · mid (summary) · fully expanded.
const _kSnapSizes = [0.2, 0.5, 0.88];

class RouteInfoCard extends StatefulWidget {
  const RouteInfoCard({
    super.key,
    required this.onClear,
    this.onShowBusDetail,
    this.onSaveFavorite,
    this.onRemoveFavorite,
  });

  final VoidCallback onClear;

  /// Invoked when the user taps the "View" button on a bus segment.
  /// Receives the segment's `tripId`. The caller is responsible for
  /// resolving it to a live trip and displaying details.
  final void Function(String tripId)? onShowBusDetail;

  /// Invoked when the user taps the bookmark icon to save the active option
  /// as a favorite route. Returns the new favorite's id on success (so the icon
  /// can switch to its filled state and later remove it), or null on failure.
  /// Null hides the icon entirely.
  final Future<String?> Function(RouteOption option)? onSaveFavorite;

  /// Invoked when the user taps the filled bookmark to remove the favorite
  /// saved during this view. Receives the id returned by [onSaveFavorite].
  /// Returns `true` when the removal succeeded.
  final Future<bool> Function(String favoriteId)? onRemoveFavorite;

  @override
  State<RouteInfoCard> createState() => _RouteInfoCardState();
}

class _RouteInfoCardState extends State<RouteInfoCard> {
  final DraggableScrollableController _controller =
      DraggableScrollableController();

  /// Option index saved during this view + the favorite's id, so the bookmark
  /// shows filled and a second tap removes it. Reset when the user switches to
  /// a different option tab.
  int? _savedOptionIndex;
  String? _savedFavoriteId;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleToggle(
    int optionIndex,
    RouteOption option,
    String? providerFavoriteId,
  ) async {
    final onSave = widget.onSaveFavorite;
    if (onSave == null || _busy) return;
    setState(() => _busy = true);

    // Id to remove: a session-saved one for this option, else the favorite this
    // view was opened from.
    final localId = _savedOptionIndex == optionIndex ? _savedFavoriteId : null;
    final removeId = localId ?? providerFavoriteId;

    if (removeId != null) {
      final onRemove = widget.onRemoveFavorite;
      final ok = onRemove == null ? false : await onRemove(removeId);
      if (!mounted) return;
      // Clear the provider marker so the bookmark stops showing as saved.
      if (ok) context.read<MapProvider>().clearActiveFavoriteId();
      setState(() {
        _busy = false;
        if (ok) {
          _savedFavoriteId = null;
          _savedOptionIndex = null;
        }
      });
    } else {
      final id = await onSave(option);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (id != null) {
          _savedFavoriteId = id;
          _savedOptionIndex = optionIndex;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _controller,
      initialChildSize: _kSnapSizes[1],
      minChildSize: _kSnapSizes[0],
      maxChildSize: _kSnapSizes[2],
      snap: true,
      snapSizes: _kSnapSizes,
      builder: (context, scrollController) {
        return Consumer<MapProvider>(
          builder: (context, provider, _) {
            final routePlan = provider.routePlan;
            final activeOptionIndex = provider.activeOptionIndex;
            final planType = provider.planType;
            final isLoading = provider.isLoadingRoute;
            final error = provider.routeError;

            final hasOptions =
                routePlan != null &&
                routePlan.found &&
                routePlan.options.isNotEmpty;
            final clampedIndex = hasOptions
                ? activeOptionIndex.clamp(0, routePlan.options.length - 1)
                : 0;
            final activeOpt = hasOptions
                ? routePlan.options[clampedIndex]
                : null;
            // Saving only makes sense for a transit plan that has bus legs.
            final canSave =
                widget.onSaveFavorite != null &&
                planType == 'transit' &&
                activeOpt != null &&
                activeOpt.segments.any((s) => s.isBus);
            // Saved when either the user saved it this session, or we're
            // displaying an existing favorite route opened from the bookmarks.
            final providerFavoriteId = provider.activeFavoriteId;
            final localSaved =
                _savedOptionIndex == clampedIndex && _savedFavoriteId != null;
            final isSaved = localSaved || providerFavoriteId != null;

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // ── Drag handle ─────────────────────────────────────────
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // ── Header row ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: Row(
                      children: [
                        Icon(
                          planType == 'walk'
                              ? Icons.directions_walk
                              : Icons.directions_bus,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Route',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (canSave)
                          IconButton(
                            onPressed: _busy
                                ? null
                                : () => _handleToggle(
                                    clampedIndex,
                                    activeOpt,
                                    providerFavoriteId,
                                  ),
                            icon: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54,
                                    ),
                                  )
                                : Icon(
                                    isSaved
                                        ? Icons.bookmark
                                        : Icons.bookmark_add_outlined,
                                    color: isSaved
                                        ? const Color(0xFFD5AC79)
                                        : Colors.white70,
                                    size: 20,
                                  ),
                            tooltip: isSaved
                                ? 'ដកចេញ​ថ្លូវធ្វើដំណើរពីចំណាំ' // "Remove from favorites" in Khmer
                                : 'រក្សាទុក​ថ្លូវធ្វើដំណើរពីជាចំណាំ', // "Save route to favorites"
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        if (canSave) const SizedBox(width: 12),
                        IconButton(
                          onPressed: widget.onClear,
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white70,
                            size: 20,
                          ),
                          tooltip: 'Clear route',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),

                  // ── Walk / Transit toggle ────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Row(
                      children: [
                        _PlanTypeChip(
                          label: 'Walk',
                          icon: Icons.directions_walk,
                          selected: planType == 'walk',
                          onTap: () => provider.setPlanType('walk'),
                        ),
                        const SizedBox(width: 8),
                        _PlanTypeChip(
                          label: 'Transit',
                          icon: Icons.directions_bus,
                          selected: planType == 'transit',
                          onTap: () => provider.setPlanType('transit'),
                        ),
                      ],
                    ),
                  ),

                  const Divider(color: Color(0xFF2A2A2A), height: 1),

                  // ── Loading / error / no-route states ───────────────────
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Finding route…',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else if (routePlan != null && !routePlan.found)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Text(
                        routePlan.message ??
                            'No route found — try a closer destination.',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else if (routePlan != null && routePlan.found) ...[
                    // ── Option tabs ────────────────────────────────────────
                    _OptionTabBar(
                      options: routePlan.options,
                      selectedIndex: activeOptionIndex.clamp(
                        0,
                        routePlan.options.length - 1,
                      ),
                      onTap: (i) => provider.setActiveOptionIndex(i),
                    ),

                    const Divider(color: Color(0xFF333333), height: 1),

                    // ── Active option details ──────────────────────────────
                    RouteOptionDetails(
                      option: routePlan.options[clampedIndex],
                      onShowBusDetail: widget.onShowBusDetail,
                    ),
                  ],

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Tab bar ──────────────────────────────────────────────────────────────────

/// Rank-based palette: fastest → slowest. Index 0 is the fastest option the
/// backend returned; later indices fade through warmer hues to red.
const List<Color> _kRankColors = [
  Color(0xFF22C55E), // emerald — fastest
  Color(0xFF84CC16), // lime
  Color(0xFFEAB308), // amber
  Color(0xFFF97316), // orange
  Color(0xFFEF4444), // red — slowest
];

Color _rankColor(int index, int total) {
  if (total <= 1) return _kRankColors.first;
  // Spread the available options evenly across the palette so 2 options use
  // green + red, 3 use green + yellow + red, etc.
  final slot = ((index / (total - 1)) * (_kRankColors.length - 1)).round();
  return _kRankColors[slot.clamp(0, _kRankColors.length - 1)];
}

String _formatRouteDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

class _OptionTabBar extends StatelessWidget {
  const _OptionTabBar({
    required this.options,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<RouteOption> options;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: List.generate(options.length, (i) {
          final opt = options[i];
          final selected = i == selectedIndex;
          final rank = _rankColor(i, options.length);
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? rank : rank.withAlpha(160),
                  borderRadius: BorderRadius.circular(12),
                  // Constant-width border so tab sizes don't jump on tap.
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: rank.withAlpha(140),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _formatRouteDuration(opt.totalEstimatedMinutes),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: selected ? 16 : 14,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Option details (summary + segment list) ───────────────────────────────────

String _formatDistance(int meters) {
  if (meters < 1000) return '${meters}m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Renders a single [RouteOption] — its summary chips, optional warning, and
/// the walk/bus segment list. Shared by [RouteInfoCard] (the live routing
/// flow) and the saved favorite-route detail sheet.
class RouteOptionDetails extends StatelessWidget {
  const RouteOptionDetails({
    super.key,
    required this.option,
    this.onShowBusDetail,
  });

  final RouteOption option;
  final void Function(String tripId)? onShowBusDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary chips row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _SummaryChip(
                icon: Icons.schedule,
                label: '~${option.totalEstimatedMinutes} min',
              ),
              _SummaryChip(
                icon: Icons.straighten,
                label: _formatDistance(option.totalDistanceMeters),
              ),
              _SummaryChip(
                icon: Icons.directions_walk,
                label: '${_formatDistance(option.totalWalkMeters)} walk',
              ),
              _SummaryChip(
                icon: Icons.swap_horiz,
                label: option.transferCount == 0
                    ? 'No transfer'
                    : '${option.transferCount} transfer'
                          '${option.transferCount > 1 ? 's' : ''}',
              ),
            ],
          ),
        ),

        // Warning banner (e.g. long walk to first stop)
        if (option.warning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Colors.orangeAccent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    option.warning!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const Divider(color: Color(0xFF2A2A2A), height: 1),

        // Segment list
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: option.segments.map((seg) {
              if (seg.isWalk) return _WalkSegmentTile(seg: seg);
              if (seg.isBus) {
                return _BusSegmentTile(
                  seg: seg,
                  onShowBusDetail: onShowBusDetail,
                );
              }
              return const SizedBox.shrink();
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Walk / Transit toggle chip ────────────────────────────────────────────────

class _PlanTypeChip extends StatelessWidget {
  const _PlanTypeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white54,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Walk segment tile ─────────────────────────────────────────────────────────

class _WalkSegmentTile extends StatelessWidget {
  const _WalkSegmentTile({required this.seg});

  final RouteSegment seg;

  @override
  Widget build(BuildContext context) {
    final dist = seg.distanceMeters;
    final mins = seg.estimatedMinutes;
    final label = [
      if (dist != null) _formatDistance(dist),
      if (mins != null) '~$mins min',
    ].join(' · ');

    final isTransfer = seg.isTransfer;

    return ListTile(
      dense: true,
      leading: Icon(
        isTransfer ? Icons.transfer_within_a_station : Icons.directions_walk,
        color: isTransfer ? Colors.orangeAccent : Colors.white54,
        size: 20,
      ),
      title: Row(
        children: [
          if (isTransfer) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade800,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Transfer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            'Walk${label.isNotEmpty ? ' $label' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
      subtitle: seg.from != null && seg.to != null
          ? Text(
              '${seg.from!.name} → ${seg.to!.name}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      isThreeLine: false,
    );
  }
}

// ── Bus segment tile ──────────────────────────────────────────────────────────

class _BusSegmentTile extends StatelessWidget {
  const _BusSegmentTile({required this.seg, this.onShowBusDetail});

  final RouteSegment seg;
  final void Function(String tripId)? onShowBusDetail;

  @override
  Widget build(BuildContext context) {
    final routeCode = seg.route?.code;
    final routeName = seg.route?.name ?? routeCode ?? 'Bus';
    final wait = seg.waitMinutes;
    final live = seg.hasLiveEta ?? false;

    // Only mark three-line when there really are 3+ subtitle rows; otherwise
    // ListTile wastes vertical space.
    final subtitleLineCount = [
      seg.boardAt != null,
      seg.alightAt != null,
      wait != null,
      seg.rideMinutes != null || seg.distanceMeters != null,
    ].where((v) => v).length;

    final tripId = seg.tripId;
    final canViewDetail = tripId != null && onShowBusDetail != null;

    return ListTile(
      dense: true,
      leading: const Icon(
        Icons.directions_bus,
        color: Colors.white70,
        size: 20,
      ),
      trailing: canViewDetail
          ? TextButton(
              onPressed: () => onShowBusDetail!(tripId),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                backgroundColor: const Color(0xFF1565C0).withAlpha(38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  Icon(Icons.chevron_right, size: 16),
                ],
              ),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (routeCode != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                routeCode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              routeName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (live)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Live',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (seg.boardAt != null)
            Text(
              'Board at ${seg.boardAt!.name}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (seg.alightAt != null)
            Text(
              'Get off at ${seg.alightAt!.name}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (wait != null)
            Text(
              live
                  ? 'Wait time in ~$wait min 🟢 Live'
                  : '~$wait min wait (estimated)',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (seg.rideMinutes != null || seg.distanceMeters != null)
            Text(
              [
                if (seg.rideMinutes != null) 'ride ~${seg.rideMinutes} min',
                if (seg.distanceMeters != null)
                  _formatDistance(seg.distanceMeters!),
              ].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          if (seg.totalLegMinutes != null)
            Text(
              'leg total ~${seg.totalLegMinutes} min',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
      isThreeLine: subtitleLineCount >= 3,
    );
  }
}

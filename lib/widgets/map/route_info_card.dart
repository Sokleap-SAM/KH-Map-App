import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/route_plan.dart';
import '../../providers/map_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/theme/app_palette.dart';

// Snap stops: collapsed (header only) · mid (summary) · fully expanded.
const _kSnapSizes = [0.2, 0.5, 0.88];

/// Friendly, localized message for a failed route-plan fetch. The raw
/// exception is intentionally never shown to the user.
String _routePlanErrorMessage(AppTexts t, RoutePlanError e) {
  switch (e) {
    case RoutePlanError.timeout:
      return t.routePlanTimeout;
    case RoutePlanError.offline:
      return t.routePlanOffline;
    case RoutePlanError.generic:
      return t.routePlanGeneric;
  }
}

/// Error state for the route info card: an icon, a friendly message and a
/// "Try again" button that re-runs the plan.
class _RoutePlanErrorView extends StatelessWidget {
  const _RoutePlanErrorView({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        children: [
          Icon(
            Icons.wifi_tethering_error_rounded,
            color: p.textFaintest,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(retryLabel),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

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
        final t = context.watch<SettingsProvider>().t;
        final p = context.palette;
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
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [
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
                        color: p.divider,
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
                          color: p.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.busShort,
                            style: TextStyle(
                              color: p.textPrimary,
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
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: p.textFaint,
                                    ),
                                  )
                                : Icon(
                                    isSaved
                                        ? Icons.bookmark
                                        : Icons.bookmark_add_outlined,
                                    color: isSaved
                                        ? const Color(0xFFD5AC79)
                                        : p.textSecondary,
                                    size: 20,
                                  ),
                            tooltip: isSaved
                                ? t.removeRouteFromFavorites
                                : t.saveRouteToFavorites,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        if (canSave) const SizedBox(width: 12),
                        IconButton(
                          onPressed: widget.onClear,
                          icon: Icon(
                            Icons.close,
                            color: p.textSecondary,
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
                          label: t.walkShort,
                          icon: Icons.directions_walk,
                          selected: planType == 'walk',
                          onTap: () => provider.setPlanType('walk'),
                        ),
                        const SizedBox(width: 8),
                        _PlanTypeChip(
                          label: t.busShort,
                          icon: Icons.directions_bus,
                          selected: planType == 'transit',
                          onTap: () => provider.setPlanType('transit'),
                        ),
                      ],
                    ),
                  ),

                  Divider(color: p.divider, height: 1),

                  // ── Loading / error / no-route states ───────────────────
                  if (isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.textFaint,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t.findingRoute,
                            style: TextStyle(
                              color: p.textFaint,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (error != null)
                    _RoutePlanErrorView(
                      message: _routePlanErrorMessage(t, error),
                      retryLabel: t.tryAgain,
                      onRetry: provider.retryRoutePlan,
                    )
                  else if (routePlan != null && !routePlan.found)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Text(
                        routePlan.message ?? t.noRouteTryLater,
                        style: TextStyle(
                          color: p.textFaint,
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

                    Divider(color: p.divider, height: 1),

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
    final t = context.watch<SettingsProvider>().t;
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
                label: t.minutesApprox(option.totalEstimatedMinutes),
              ),
              _SummaryChip(
                icon: Icons.straighten,
                label: _formatDistance(option.totalDistanceMeters),
              ),
              _SummaryChip(
                icon: Icons.directions_walk,
                label: t.walkDistance(
                  _formatDistance(option.totalWalkMeters),
                ),
              ),
              _SummaryChip(
                icon: Icons.swap_horiz,
                label: option.transferCount == 0
                    ? t.noTransfers
                    : t.transfersCount(option.transferCount),
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

        Divider(color: context.palette.divider, height: 1),

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
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: p.textFaint),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: p.textSecondary, fontSize: 12),
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
    final p = context.palette;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1565C0) : p.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : p.textFaint,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : p.textFaint,
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
    final settings = context.watch<SettingsProvider>();
    final lang = settings.languageCode;
    final t = settings.t;
    final dist = seg.distanceMeters;
    final mins = seg.estimatedMinutes;
    final label = [
      if (dist != null) _formatDistance(dist),
      if (mins != null) t.minutesApprox(mins),
    ].join(' · ');

    final isTransfer = seg.isTransfer;
    final p = context.palette;

    return ListTile(
      dense: true,
      leading: Icon(
        isTransfer ? Icons.transfer_within_a_station : Icons.directions_walk,
        color: isTransfer ? Colors.orangeAccent : p.textFaint,
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
            t.walkSegment(label),
            style: TextStyle(color: p.textPrimary, fontSize: 14),
          ),
        ],
      ),
      subtitle: seg.from != null && seg.to != null
          ? Text(
              '${seg.from!.localizedName(lang)} → ${seg.to!.localizedName(lang)}',
              style: TextStyle(color: p.textFaint, fontSize: 12),
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
    final settings = context.watch<SettingsProvider>();
    final lang = settings.languageCode;
    final t = settings.t;
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
    final p = context.palette;

    return ListTile(
      dense: true,
      leading: Icon(
        Icons.directions_bus,
        color: p.textSecondary,
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.view,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16),
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
              style: TextStyle(
                color: p.textPrimary,
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
              t.boardAtStop(seg.boardAt!.localizedName(lang)),
              style: TextStyle(color: p.textFaint, fontSize: 12),
            ),
          if (seg.alightAt != null)
            Text(
              t.alightAtStop(seg.alightAt!.localizedName(lang)),
              style: TextStyle(color: p.textFaint, fontSize: 12),
            ),
          if (wait != null)
            Text(
              live ? t.waitLive(wait) : t.waitEstimated(wait),
              style: TextStyle(color: p.textFaint, fontSize: 12),
            ),
          if (seg.rideMinutes != null || seg.distanceMeters != null)
            Text(
              [
                if (seg.rideMinutes != null) t.rideMinutes(seg.rideMinutes!),
                if (seg.distanceMeters != null)
                  _formatDistance(seg.distanceMeters!),
              ].join(' · '),
              style: TextStyle(color: p.textFaint, fontSize: 12),
            ),
          if (seg.totalLegMinutes != null)
            Text(
              t.totalLegMinutes(seg.totalLegMinutes!),
              style: TextStyle(color: p.textFaintest, fontSize: 11),
            ),
        ],
      ),
      isThreeLine: subtitleLineCount >= 3,
    );
  }
}

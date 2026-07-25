import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/route_plan.dart';
import '../../models/route_progress.dart';
import '../../models/trip.dart';
import '../../providers/map_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/transit_provider.dart';
import '../../utils/constants/text_strings.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(
        children: [
          const Icon(
            Icons.wifi_tethering_error_rounded,
            color: Colors.white38,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
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
  void initState() {
    super.initState();
    _controller.addListener(_reportSheetVisibility);
    // The sheet opens expanded — report visible now so the 60 s alternative
    // refresh runs from the start of the trip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MapProvider>().setRouteSheetVisible(true);
    });
  }

  /// Tells the provider whether the tabs are on screen (sheet not collapsed),
  /// so the 60 s refresh of the alternative tabs only runs when they're visible.
  void _reportSheetVisibility() {
    if (!mounted) return;
    final visible = _controller.isAttached && _controller.size > 0.3;
    context.read<MapProvider>().setRouteSheetVisible(visible);
  }

  @override
  void dispose() {
    _controller.removeListener(_reportSheetVisibility);
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
                        Expanded(
                          child: Text(
                            t.busShort,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Live "arrive in ~X min" countdown, recomputed locally
                        // from GPS progress — no re-plan.
                        if (provider.routeProgress != null) ...[
                          _LiveEtaPill(progress: provider.routeProgress!, t: t),
                          const SizedBox(width: 8),
                        ],
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
                                ? t.removeRouteFromFavorites
                                : t.saveRouteToFavorites,
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

                  // ── Faster-route suggestion (non-disruptive) ─────────────
                  if (provider.fasterSuggestion != null)
                    _FasterRouteBanner(
                      savingMinutes: provider.fasterSavingMinutes ?? 0,
                      onSwitch: provider.switchToFasterRoute,
                      onDismiss: provider.dismissFasterSuggestion,
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

                  const Divider(color: Color(0xFF2A2A2A), height: 1),

                  // ── Loading / error / no-route states ───────────────────
                  if (isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            t.findingRoute,
                            style: const TextStyle(
                              color: Colors.white54,
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
                      showLiveProgress: true,
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

/// Header pill showing the live "arrive in ~X min" countdown and current phase
/// (walking / waiting / riding / arrived). Fed by [MapProvider.routeProgress],
/// which is recomputed locally each second — no network, no re-plan.
class _LiveEtaPill extends StatelessWidget {
  const _LiveEtaPill({required this.progress, required this.t});

  final RouteProgress progress;
  final AppTexts t;

  @override
  Widget build(BuildContext context) {
    final arrived = progress.isArrived;
    final icon = switch (progress.phase) {
      RoutePhase.walking => Icons.directions_walk,
      RoutePhase.waiting => Icons.schedule,
      RoutePhase.riding => Icons.directions_bus,
      RoutePhase.arrived => Icons.check_circle,
    };
    final color = arrived ? Colors.greenAccent : const Color(0xFF64B5F6);
    final label = arrived
        ? t.arrivedLabel
        : t.arriveInApprox(progress.minutesRemaining);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dismissible banner offering a faster route found by the background shadow
/// re-plan. Purely a suggestion — tapping "Switch" adopts it, the ✕ dismisses
/// it; neither happens automatically.
class _FasterRouteBanner extends StatelessWidget {
  const _FasterRouteBanner({
    required this.savingMinutes,
    required this.onSwitch,
    required this.onDismiss,
  });

  final int savingMinutes;
  final VoidCallback onSwitch;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E).withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF22C55E).withAlpha(120)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Color(0xFF4ADE80), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.fasterRouteSave(savingMinutes),
              style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onSwitch,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color(0xFF22C55E),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              t.switchRoute,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            tooltip: t.close,
          ),
        ],
      ),
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
    this.showLiveProgress = false,
  });

  final RouteOption option;
  final void Function(String tripId)? onShowBusDetail;

  /// When true (the live routing flow), the bus leg the user is currently on
  /// gets a live "reach your stop in N min" row from `GET /transit/eta`. The
  /// saved favorite-route sheet leaves this false — there's no live trip.
  final bool showLiveProgress;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    // Which leg the user is on now, so only the active bus leg shows live ETA.
    final progress = showLiveProgress
        ? context.watch<MapProvider>().routeProgress
        : null;
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
                label: t.walkDistance(_formatDistance(option.totalWalkMeters)),
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

        const Divider(color: Color(0xFF2A2A2A), height: 1),

        // Segment list with a vertical progress spine + live "you are here" dot.
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              for (var i = 0; i < option.segments.length; i++)
                _buildSegment(
                  option.segments[i],
                  i,
                  option.segments.length,
                  progress,
                ),
              _DestinationRow(
                label: t.destinationLabel,
                arrived: progress?.isArrived ?? false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegment(
    RouteSegment seg,
    int index,
    int total,
    RouteProgress? progress,
  ) {
    final activeIdx = progress?.activeSegmentIndex;
    final isDone = activeIdx != null && index < activeIdx;
    final isActive = activeIdx != null && index == activeIdx;
    final state = isDone
        ? _RailState.done
        : isActive
        ? _RailState.active
        : _RailState.upcoming;

    // The active walk leg shrinks to what's left as the user advances along it.
    final Widget base;
    if (seg.isWalk) {
      base = _WalkSegmentTile(
        seg: seg,
        remainingFraction: isActive
            ? (1 - (progress?.fractionAlongSegment ?? 0))
            : null,
      );
    } else if (seg.isBus) {
      // The next bus leg (which may still be ahead while walking to it) carries
      // live ETA: the real wait before boarding, then the ride once aboard.
      final isLiveBusLeg = progress?.busLegIndex == index;
      final riding = progress?.phase == RoutePhase.riding;
      base = _BusSegmentTile(
        seg: seg,
        onShowBusDetail: onShowBusDetail,
        liveBoardSeconds: isLiveBusLeg && !riding
            ? progress?.busBoardSeconds
            : null,
        liveAlightSeconds: isLiveBusLeg && riding
            ? progress?.busAlightSeconds
            : null,
      );
    } else {
      return const SizedBox.shrink();
    }

    // Completed legs dim; the spine rail stays bright to show the travelled path.
    final tile = isDone ? Opacity(opacity: 0.5, child: base) : base;

    // The tile sets the row height; the spine rail is painted beside it in a
    // Stack. (IntrinsicHeight mis-measures ListTile/AnimatedCrossFade heights,
    // which overflows tall bus tiles.)
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _SpineRail(
            state: state,
            isFirst: index == 0,
            isLast: false, // the destination row terminates the spine
            isBus: seg.isBus,
            // The origin node (leg 0's start) reads green.
            endpointColor: index == 0 ? const Color(0xFF22C55E) : null,
            youAreHereFraction: isActive
                ? (progress?.fractionAlongSegment ?? 0)
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: tile,
        ),
      ],
    );
  }
}

// ── Progress spine (vertical timeline + live "you are here" dot) ───────────────

enum _RailState { done, active, upcoming }

/// The left-gutter rail for one itinerary row: the connecting line (solid =
/// travelled, grey/dashed = still ahead), the node dot, and — on the active
/// leg — the live "you are here" marker positioned by `youAreHereFraction`.
class _SpineRail extends StatelessWidget {
  const _SpineRail({
    required this.state,
    required this.isFirst,
    required this.isLast,
    required this.isBus,
    this.endpointColor,
    this.youAreHereFraction,
  });

  final _RailState state;
  final bool isFirst;
  final bool isLast;
  final bool isBus;
  final Color? endpointColor;
  final double? youAreHereFraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      child: CustomPaint(
        painter: _SpinePainter(
          state: state,
          isFirst: isFirst,
          isLast: isLast,
          isBus: isBus,
          endpointColor: endpointColor,
          youAreHereFraction: youAreHereFraction,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SpinePainter extends CustomPainter {
  _SpinePainter({
    required this.state,
    required this.isFirst,
    required this.isLast,
    required this.isBus,
    this.endpointColor,
    this.youAreHereFraction,
  });

  final _RailState state;
  final bool isFirst;
  final bool isLast;
  final bool isBus;
  final Color? endpointColor;
  final double? youAreHereFraction;

  static const _travelled = Color(0xFF64B5F6);
  static const _busColor = Color(0xFF1565C0);
  static const _ahead = Color(0xFF3A3A3A);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    const nodeY = 20.0;
    const nodeR = 5.0;

    final aboveTravelled = state != _RailState.upcoming;
    final belowTravelled = state == _RailState.done;

    void line(double y1, double y2, Color color, {bool dashed = false}) {
      final p = Paint()
        ..color = color
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      if (!dashed) {
        canvas.drawLine(Offset(cx, y1), Offset(cx, y2), p);
        return;
      }
      const dash = 4.0, gap = 4.0;
      var y = y1;
      while (y < y2) {
        canvas.drawLine(Offset(cx, y), Offset(cx, (y + dash).clamp(y1, y2)), p);
        y += dash + gap;
      }
    }

    if (!isFirst) {
      line(0, nodeY, aboveTravelled ? _travelled : _ahead);
    }
    if (!isLast) {
      final color = belowTravelled ? (isBus ? _busColor : _travelled) : _ahead;
      line(nodeY, size.height, color, dashed: !isBus && !belowTravelled);
    }

    final nodeColor =
        endpointColor ?? (state == _RailState.upcoming ? _ahead : _travelled);
    canvas.drawCircle(Offset(cx, nodeY), nodeR, Paint()..color = nodeColor);

    final f = youAreHereFraction;
    if (f != null) {
      final y = nodeY + (size.height - nodeY) * f.clamp(0.0, 1.0);
      canvas.drawCircle(Offset(cx, y), 7, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(cx, y),
        4.5,
        Paint()..color = const Color(0xFF22C55E),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpinePainter old) =>
      old.state != state ||
      old.isFirst != isFirst ||
      old.isLast != isLast ||
      old.isBus != isBus ||
      old.endpointColor != endpointColor ||
      old.youAreHereFraction != youAreHereFraction;
}

/// The terminating node of the spine — the destination marker + label.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.label, required this.arrived});

  final String label;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: _SpineRail(
            state: arrived ? _RailState.done : _RailState.upcoming,
            isFirst: false,
            isLast: true,
            isBus: false,
            endpointColor: const Color(0xFFEF4444),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.place, color: Color(0xFFEF4444), size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: arrived ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
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
  const _WalkSegmentTile({required this.seg, this.remainingFraction});

  final RouteSegment seg;

  /// 0..1 of the walk still ahead when this is the leg the user is on. When set
  /// (< 1), the tile shows the remaining distance/time instead of the full leg.
  final double? remainingFraction;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.languageCode;
    final t = settings.t;
    final frac = remainingFraction;
    final showRemaining = frac != null && frac < 0.999;
    final dist = seg.distanceMeters;
    final mins = seg.estimatedMinutes;
    final effDist = showRemaining && dist != null
        ? (dist * frac).round()
        : dist;
    final effMins = showRemaining && mins != null ? (mins * frac).ceil() : mins;
    final label = [
      if (effDist != null) _formatDistance(effDist),
      if (effMins != null) t.minutesApprox(effMins),
    ].join(' · ');
    final titleText = showRemaining
        ? t.walkRemaining(label)
        : t.walkSegment(label);

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
            titleText,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
      subtitle: seg.from != null && seg.to != null
          ? Text(
              '${seg.from!.localizedName(lang)} → ${seg.to!.localizedName(lang)}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            )
          : null,
      isThreeLine: false,
    );
  }
}

// ── Bus segment tile ──────────────────────────────────────────────────────────

class _BusSegmentTile extends StatefulWidget {
  const _BusSegmentTile({
    required this.seg,
    this.onShowBusDetail,
    this.liveBoardSeconds,
    this.liveAlightSeconds,
  });

  final RouteSegment seg;
  final void Function(String tripId)? onShowBusDetail;

  /// Live ETA (seconds) of the bus to the board stop — "arrives in N", shown in
  /// place of the plan's static estimate while approaching/waiting. Null when
  /// unavailable.
  final int? liveBoardSeconds;

  /// Live ETA (seconds) to the alight stop, shown once aboard. Null otherwise.
  final int? liveAlightSeconds;

  @override
  State<_BusSegmentTile> createState() => _BusSegmentTileState();
}

class _BusSegmentTileState extends State<_BusSegmentTile> {
  /// Whether the full ride stop-list (Phase 1) is expanded.
  bool _stopsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final seg = widget.seg;
    final onShowBusDetail = widget.onShowBusDetail;
    final liveBoardSeconds = widget.liveBoardSeconds;
    final liveAlightSeconds = widget.liveAlightSeconds;
    final settings = context.watch<SettingsProvider>();
    final lang = settings.languageCode;
    final t = settings.t;
    final routeCode = seg.route?.code;
    final routeName = seg.route?.name ?? routeCode ?? 'Bus';
    final wait = seg.waitMinutes;
    final live = seg.hasLiveEta ?? false;

    // Phase 2: upcoming arrivals at the board stop. With a genuine "next bus"
    // (2+), a dedicated block below owns the arrival lines, so the single
    // wait/live subtitle row is suppressed to avoid showing the ETA twice.
    final upcoming = seg.busEtas;
    final showUpcoming = upcoming.length >= 2;

    // Only mark three-line when there really are 3+ subtitle rows; otherwise
    // ListTile wastes vertical space.
    final subtitleLineCount = [
      seg.boardAt != null,
      seg.alightAt != null,
      !showUpcoming && (liveBoardSeconds != null || wait != null),
      seg.rideMinutes != null || seg.distanceMeters != null,
    ].where((v) => v).length;

    final tripId = seg.tripId;
    final canViewDetail = tripId != null && onShowBusDetail != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          leading: const Icon(
            Icons.directions_bus,
            color: Colors.white70,
            size: 20,
          ),
          trailing: canViewDetail
              ? TextButton(
                  onPressed: () => onShowBusDetail(tripId),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              if (seg.alightAt != null)
                Text(
                  t.alightAtStop(seg.alightAt!.localizedName(lang)),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              // Live "bus arrives in N" (bus → board stop) wins over the static
              // estimate — the deadline to reach the stop, so the user can hurry.
              // Suppressed when the upcoming-buses block below owns the arrivals.
              if (!showUpcoming)
                if (liveBoardSeconds != null)
                  Text(
                    liveBoardSeconds <= 0
                        ? t.busArrivingNow
                        : t.busArrivesIn((liveBoardSeconds / 60).round()),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (wait != null)
                  Text(
                    live ? t.busArrivesIn(wait) : t.busArrivesInEstimated(wait),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
              if (seg.rideMinutes != null || seg.distanceMeters != null)
                Text(
                  [
                    if (seg.rideMinutes != null)
                      t.rideMinutes(seg.rideMinutes!),
                    if (seg.distanceMeters != null)
                      _formatDistance(seg.distanceMeters!),
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              // Once aboard: live "reach your stop in N min".
              if (liveAlightSeconds != null)
                Text(
                  liveAlightSeconds <= 0
                      ? t.atYourStop
                      : t.reachYourStopIn((liveAlightSeconds / 60).round()),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (seg.totalLegMinutes != null)
                Text(
                  t.totalLegMinutes(seg.totalLegMinutes!),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
          isThreeLine: subtitleLineCount >= 3,
        ),

        // Phase 2 — current + next bus at the board stop.
        if (showUpcoming)
          _UpcomingBuses(
            etas: upcoming,
            tripId: seg.tripId,
            boardStopIndex: seg.boardAt?.stopIndex,
            liveLeadSeconds: liveBoardSeconds,
            live: live,
            t: t,
          ),

        // Phase 1 — expandable full ride stop-list.
        if (seg.intermediateStops.isNotEmpty)
          _RideStopList(
            seg: seg,
            expanded: _stopsExpanded,
            onToggle: () => setState(() => _stopsExpanded = !_stopsExpanded),
            lang: lang,
            t: t,
          ),
      ],
    );
  }
}

// ── Phase 2: upcoming buses (current + next) ─────────────────────────────────

/// Compact "current + next vehicle" panel for a bus leg, from
/// [RouteSegment.busEtas]. The lead row prefers the live MQTT ETA and shows how
/// many stops away the recommended bus is (from the live trip's
/// `currentStopIndex`); later rows come from the planned arrival list.
class _UpcomingBuses extends StatelessWidget {
  const _UpcomingBuses({
    required this.etas,
    required this.tripId,
    required this.boardStopIndex,
    required this.liveLeadSeconds,
    required this.live,
    required this.t,
  });

  final List<int> etas;
  final String? tripId;
  final int? boardStopIndex;
  final int? liveLeadSeconds;
  final bool live;
  final AppTexts t;

  @override
  Widget build(BuildContext context) {
    // Lead-bus "N stops away" from the live trip position (MQTT).
    int? stopsAway;
    final boardIdx = boardStopIndex;
    final leadTripId = tripId;
    if (leadTripId != null && boardIdx != null) {
      for (final Trip tr in context.watch<TransitProvider>().trips) {
        if (tr.id == leadTripId) {
          final away = boardIdx - tr.currentStopIndex;
          if (away >= 0) stopsAway = away;
          break;
        }
      }
    }

    final lead = liveLeadSeconds;
    final leadMinutes = lead != null ? (lead / 60).round() : etas.first;

    final rows = <Widget>[
      _busRow(
        index: 1,
        minutes: leadMinutes,
        stopsAway: stopsAway,
        isLead: true,
      ),
    ];
    for (var i = 1; i < etas.length && i < 3; i++) {
      rows.add(
        _busRow(index: i + 1, minutes: etas[i], stopsAway: null, isLead: false),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(56, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: rows),
    );
  }

  Widget _busRow({
    required int index,
    required int minutes,
    required int? stopsAway,
    required bool isLead,
  }) {
    final urgent = isLead && minutes <= 3;
    final Color color = isLead
        ? (urgent ? Colors.greenAccent : const Color(0xFF4ADE80))
        : Colors.white54;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.directions_bus, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            t.busNumber(index),
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const Spacer(),
          Text(
            urgent ? t.busArrivingNow : t.minutesApprox(minutes),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (stopsAway != null) ...[
            const SizedBox(width: 8),
            Text(
              t.stopsAway(stopsAway),
              style: TextStyle(color: color.withAlpha(200), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Phase 1: expandable ride stop-list ───────────────────────────────────────

/// Collapsible full stop-list for a bus leg — the ridden sequence
/// board → intermediate stops → alight, each intermediate with its cumulative
/// ETA from the board stop.
class _RideStopList extends StatelessWidget {
  const _RideStopList({
    required this.seg,
    required this.expanded,
    required this.onToggle,
    required this.lang,
    required this.t,
  });

  final RouteSegment seg;
  final bool expanded;
  final VoidCallback onToggle;
  final String lang;
  final AppTexts t;

  @override
  Widget build(BuildContext context) {
    final count = seg.intermediateStops.length;
    final rideMin = seg.rideMinutes;
    final headerLabel = [
      t.stopsCount(count),
      if (rideMin != null) t.minutesApprox(rideMin),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: const Color(0xFF64B5F6),
                ),
                const SizedBox(width: 4),
                Text(
                  headerLabel,
                  style: const TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _stopColumn(),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _stopColumn() {
    return Padding(
      padding: const EdgeInsets.only(left: 56, right: 16, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (seg.boardAt != null) _stopRow(seg.boardAt!, anchor: true),
          for (final s in seg.intermediateStops) _stopRow(s, anchor: false),
          if (seg.alightAt != null) _stopRow(seg.alightAt!, anchor: true),
        ],
      ),
    );
  }

  Widget _stopRow(SegmentStop s, {required bool anchor}) {
    final eta = anchor ? null : s.cumulativeMinutesFromBoard;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: anchor ? 10 : 7,
            height: anchor ? 10 : 7,
            decoration: BoxDecoration(
              color: anchor ? const Color(0xFF64B5F6) : Colors.white30,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.localizedName(lang),
              style: TextStyle(
                color: anchor ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: anchor ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (eta != null)
            Text(
              t.minutesApprox(eta),
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

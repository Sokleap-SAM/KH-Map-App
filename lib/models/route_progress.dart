/// Which leg of the journey the user is currently on. Drives whether progress
/// is tracked from phone GPS (walking) or from the live bus (riding), and lets
/// the UI silence GPS-based behaviour while on a bus.
enum RoutePhase { walking, waiting, riding, arrived }

/// A client-side snapshot of how far the user is through the active route
/// option, recomputed each tick from the latest GPS fix — no network. Lets the
/// route card show a live "arrive in ~X min" countdown and a per-leg progress
/// bar without re-planning.
class RouteProgress {
  /// Index into `RouteOption.segments` of the leg the user is currently on.
  final int activeSegmentIndex;

  final RoutePhase phase;

  /// 0..1 progress along the active segment.
  final double fractionAlongSegment;

  /// Straight-remaining distance to the destination in metres.
  final int metersRemaining;

  /// Estimated minutes to the destination. When live bus ETA is available for
  /// the next bus leg, this folds in the real wait at the board stop (see
  /// [busWaitSeconds]) instead of the plan's static wait.
  final int minutesRemaining;

  /// Index of the next incomplete bus leg that live ETA applies to, or null
  /// when there's no live bus data (no upcoming bus, or ETA unavailable).
  final int? busLegIndex;

  /// Live ETA in seconds of the bus to [busLegIndex]'s board stop — i.e. "bus
  /// arrives in N". Shown so the user knows the deadline to reach the stop
  /// (more actionable than a "wait", which hides a would-be-missed as 0). Null
  /// without live data.
  final int? busBoardSeconds;

  /// Live ETA in seconds of the bus to [busLegIndex]'s alight stop. Null
  /// without live data.
  final int? busAlightSeconds;

  const RouteProgress({
    required this.activeSegmentIndex,
    required this.phase,
    required this.fractionAlongSegment,
    required this.metersRemaining,
    required this.minutesRemaining,
    this.busLegIndex,
    this.busBoardSeconds,
    this.busAlightSeconds,
  });

  bool get isArrived => phase == RoutePhase.arrived;

  /// True when nothing the UI cares about has changed, so a rebuild can be
  /// skipped. Compares at display granularity (whole minutes, ~1% progress).
  bool sameAs(RouteProgress? o) =>
      o != null &&
      o.activeSegmentIndex == activeSegmentIndex &&
      o.phase == phase &&
      o.minutesRemaining == minutesRemaining &&
      o.busLegIndex == busLegIndex &&
      o.busBoardSeconds == busBoardSeconds &&
      o.busAlightSeconds == busAlightSeconds &&
      (o.fractionAlongSegment - fractionAlongSegment).abs() < 0.01;
}

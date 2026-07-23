/// Selectable reporting window for the admin dashboard. `start` is always
/// anchored at midnight, so `day` means "since 00:00 today" (not rolling 24h).
enum DashboardPeriod { day, week, month, year }

extension DashboardPeriodX on DashboardPeriod {
  /// Query-string value expected by the backend.
  String get value => name; // day | week | month | year

  /// Short Khmer label for the tab.
  String get labelKm {
    switch (this) {
      case DashboardPeriod.day:
        return 'ថ្ងៃ';
      case DashboardPeriod.week:
        return 'សប្ដាហ៍';
      case DashboardPeriod.month:
        return 'ខែ';
      case DashboardPeriod.year:
        return 'ឆ្នាំ';
    }
  }

  /// Short English label for the tab.
  String get labelEn {
    switch (this) {
      case DashboardPeriod.day:
        return 'Day';
      case DashboardPeriod.week:
        return 'Week';
      case DashboardPeriod.month:
        return 'Month';
      case DashboardPeriod.year:
        return 'Year';
    }
  }

  /// Label for the active [languageCode] ('en' → English, else Khmer).
  String label(String languageCode) =>
      languageCode == 'en' ? labelEn : labelKm;
}

/// Live fleet state — not bound to the selected window.
class DashboardCurrent {
  final int routes;
  final int activeRoutes;
  final int stops;
  final int buses;
  final int drivers;
  final int driversOnShift;
  final int activeTrips;
  final int scheduledTrips;

  const DashboardCurrent({
    required this.routes,
    required this.activeRoutes,
    required this.stops,
    required this.buses,
    required this.drivers,
    required this.driversOnShift,
    required this.activeTrips,
    required this.scheduledTrips,
  });

  factory DashboardCurrent.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return DashboardCurrent(
      routes: n('routes'),
      activeRoutes: n('activeRoutes'),
      stops: n('stops'),
      buses: n('buses'),
      drivers: n('drivers'),
      driversOnShift: n('driversOnShift'),
      activeTrips: n('activeTrips'),
      scheduledTrips: n('scheduledTrips'),
    );
  }
}

/// Counts bound to the selected window (since midnight `start`).
class DashboardInPeriod {
  final int trips;
  final int completedTrips;
  final int cancelledTrips;
  final int newRoutes;

  const DashboardInPeriod({
    required this.trips,
    required this.completedTrips,
    required this.cancelledTrips,
    required this.newRoutes,
  });

  factory DashboardInPeriod.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return DashboardInPeriod(
      trips: n('trips'),
      completedTrips: n('completedTrips'),
      cancelledTrips: n('cancelledTrips'),
      newRoutes: n('newRoutes'),
    );
  }
}

/// The admin dashboard payload: live/simulation mode, the selected window, and
/// the split current/in-period counts.
class AdminDashboard {
  /// "live" | "simulation".
  final String mode;

  /// "day" | "week" | "month" | "year".
  final String period;

  final DateTime? windowStart;
  final DateTime? windowEnd;

  final DashboardCurrent current;
  final DashboardInPeriod inPeriod;

  const AdminDashboard({
    required this.mode,
    required this.period,
    required this.windowStart,
    required this.windowEnd,
    required this.current,
    required this.inPeriod,
  });

  bool get isSimulation => mode == 'simulation';

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final window = json['window'] as Map<String, dynamic>?;
    DateTime? parse(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return AdminDashboard(
      mode: (json['mode'] as String?) ?? 'live',
      period: (json['period'] as String?) ?? 'day',
      windowStart: parse(window?['start']),
      windowEnd: parse(window?['end']),
      current: DashboardCurrent.fromJson(
        (json['current'] as Map<String, dynamic>?) ?? const {},
      ),
      inPeriod: DashboardInPeriod.fromJson(
        (json['inPeriod'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}

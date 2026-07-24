import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/route_stop.dart';
import '../../models/trip.dart';
import '../../providers/driver_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/transit_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/theme/app_palette.dart';
import '../../widgets/transit/stop_timeline.dart';

/// Full-screen trip detail. Shows "Start trip" / "Cancel trip" depending
/// on status. After a successful start/cancel we pop so the user lands
/// back on the Home (which now reflects the new state).
///
/// `/drivers/me/trips` returns `route`/`bus` as bare ids and carries no
/// stop list, so we fetch the route's stops + label from the rider-facing
/// transit endpoints to render a meaningful screen.
class DriverTripDetailScreen extends StatefulWidget {
  final String tripId;
  const DriverTripDetailScreen({super.key, required this.tripId});

  @override
  State<DriverTripDetailScreen> createState() => _DriverTripDetailScreenState();
}

class _DriverTripDetailScreenState extends State<DriverTripDetailScreen> {
  final TransitService _transit = TransitService();
  List<RouteStop> _stops = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStops());
  }

  Future<void> _loadStops() async {
    final trip = _findTrip(context.read<DriverProvider>());
    final routeId = trip?.routeId;
    if (routeId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final stops = await _transit.fetchRouteStops(routeId)
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Trip? _findTrip(DriverProvider d) {
    for (final t in d.allTrips) {
      if (t.id == widget.tripId) return t;
    }
    if (d.activeTrip?.id == widget.tripId) return d.activeTrip;
    return null;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in-progress':
        return Colors.green;
      case 'scheduled':
        return Colors.blue;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.black54;
    }
  }

  /// "ALL STOPS" timeline matching the rider map sheet, themed via AppPalette.
  Widget _buildStopsSection(Trip trip) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              context.watch<SettingsProvider>().t.allStopsHeader,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                context.watch<SettingsProvider>().t.noStopData,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textFaintest),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  for (int i = 0; i < _stops.length; i++)
                    StopTimelineTile(
                      index: i,
                      activeIndex: trip.nextStopIndex,
                      totalStops: _stops.length,
                      stopName: _stops[i].localizedStopName(
                        context.watch<SettingsProvider>().languageCode,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DriverProvider>();
    final t = context.watch<SettingsProvider>().t;
    final trip = _findTrip(d);
    final assignedBus = d.profile?.assignedBusId;

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.tripDetails)),
        body: const Center(child: Text('Trip not found.')),
      );
    }

    // Show the Start button whenever this scheduled trip is on the driver's
    // bus; gate *enabling* it on being on-shift + having GPS permission so the
    // reason is visible rather than the button silently vanishing.
    final isMineScheduled =
        trip.status == 'scheduled' && trip.busId == assignedBus;
    final offShift = d.shiftState == DriverShiftState.offShift;
    final canStart = isMineScheduled && !offShift && d.hasLocationPermission;
    final canCancel = trip.isInProgress;

    final header = d.routeTitle(trip, fallback: t.tripFallbackName);
    final busNumber = d.busNumberOf(trip);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(header),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(trip.status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  trip.status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (busNumber != null) Text(t.busNumberLabel(busNumber)),
            ],
          ),
          const SizedBox(height: 16),
          _buildStopsSection(trip),
          const SizedBox(height: 24),
          if (isMineScheduled) ...[
            ElevatedButton(
              onPressed: (d.busy || !canStart)
                  ? null
                  : () async {
                      final ok = await context.read<DriverProvider>().startTrip(
                        trip.id,
                      );
                      if (ok && context.mounted) Navigator.of(context).pop();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                t.startTrip,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            if (offShift)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.turnOnShiftFirst,
                  style: const TextStyle(color: Colors.orange),
                ),
              )
            else if (!d.hasLocationPermission)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  t.locationPermissionRequired,
                  style: const TextStyle(color: Colors.orange),
                ),
              ),
          ],
          if (canCancel)
            ElevatedButton(
              onPressed: d.busy
                  ? null
                  : () async {
                      final ok = await context
                          .read<DriverProvider>()
                          .cancelTrip();
                      if (ok && context.mounted) Navigator.of(context).pop();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                t.cancelTrip,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          if (d.lastError != null) ...[
            const SizedBox(height: 12),
            Text(d.lastError!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}

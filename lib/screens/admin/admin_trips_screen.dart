import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/trip.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import 'admin_trip_create_screen.dart';

/// Trip management — schedule trips, drive their status by hand, delete them.
///
/// Defaults to `/transit/trips/active` rather than the full list: every trip
/// carries its route's entire `allStops` array, so the unfiltered endpoint gets
/// heavy fast (40 stops × N trips). "All" is available but opt-in.
class AdminTripsScreen extends StatefulWidget {
  const AdminTripsScreen({super.key});

  @override
  State<AdminTripsScreen> createState() => _AdminTripsScreenState();
}

class _AdminTripsScreenState extends State<AdminTripsScreen> {
  final AdminService _service = AdminService();

  List<Trip> _trips = const [];
  bool _loading = true;
  String? _error;

  /// Active-only uses the cheap endpoint; toggling it off pulls every trip.
  bool _activeOnly = true;
  String? _statusFilter;

  /// Client-side search over what's loaded, like the stop and route searches:
  /// `/transit/trips` takes no query parameters.
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final trips = _activeOnly
          ? await _service.fetchActiveTrips()
          : await _service.fetchAllTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  /// Status chip AND search, applied together.
  List<Trip> get _filtered {
    final q = _search.trim().toLowerCase();
    return _trips.where((trip) {
      if (_statusFilter != null && trip.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      // Route code ("3"), route name ("Line 3 Outbound"), bus number and plate
      // — the four things shown on a row, so anything visible is findable.
      return (trip.routeNumber?.toLowerCase().contains(q) ?? false) ||
          trip.direction.toLowerCase().contains(q) ||
          (trip.routeName?.toLowerCase().contains(q) ?? false) ||
          (trip.busNumber?.toLowerCase().contains(q) ?? false) ||
          (trip.busLicensePlate?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminTripCreateScreen()),
    );
    if (created == true && mounted) {
      _snack(context.read<SettingsProvider>().t.tripCreated);
      _load();
    }
  }

  /// Manual status override — how an admin cancels or completes a trip that the
  /// simulator or driver won't finish on its own.
  Future<void> _changeStatus(Trip trip) async {
    final t = context.read<SettingsProvider>().t;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.changeStatus),
        children: [
          for (final status in TripStatuses.all)
            ListTile(
              leading: Icon(
                trip.status == status
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _statusColor(status),
              ),
              title: Text(_statusLabel(t, status)),
              onTap: () => Navigator.of(ctx).pop(status),
            ),
        ],
      ),
    );
    if (picked == null || picked == trip.status) return;

    try {
      await _service.updateTrip(trip.id, status: picked);
      if (!mounted) return;
      _snack(t.tripUpdated);
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(t.failedWith(e is AdminApiException ? e.message : e.toString()));
    }
  }

  Future<void> _delete(Trip trip) async {
    final t = context.read<SettingsProvider>().t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteTripTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${trip.routeNumber} · ${trip.busNumber}'),
            const SizedBox(height: 8),
            Text(
              t.deleteTripWarning,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              t.confirmWord,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _service.deleteTrip(trip.id);
      if (!mounted) return;
      _snack(t.tripDeleted);
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(t.failedWith(e is AdminApiException ? e.message : e.toString()));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _statusLabel(AppTexts t, String status) => switch (status) {
        TripStatuses.scheduled => t.tripStatusScheduled,
        TripStatuses.inProgress => t.tripStatusInProgress,
        TripStatuses.completed => t.tripStatusCompleted,
        TripStatuses.cancelled => t.tripStatusCancelled,
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        TripStatuses.inProgress => Colors.green,
        TripStatuses.scheduled => Colors.orange,
        TripStatuses.completed => Colors.blueGrey,
        TripStatuses.cancelled => Colors.red,
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.manageTrips),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_trips_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(t.newTrip),
      ),
      body: Column(
        children: [
          _buildFilters(t),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.searchTripsHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(child: _buildBody(t)),
        ],
      ),
    );
  }

  Widget _buildFilters(AppTexts t) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(t.activeOnly),
              selected: _activeOnly,
              // Switching endpoints, so this refetches rather than filtering
              // what's already loaded.
              onSelected: (v) {
                setState(() {
                  _activeOnly = v;
                  _statusFilter = null;
                });
                _load();
              },
            ),
          ),
          const VerticalDivider(width: 16),
          _chip(t.all, _statusFilter == null,
              () => setState(() => _statusFilter = null)),
          // With active-only on, the other two states can't appear — offering
          // them would just yield an empty list.
          for (final status
              in _activeOnly ? TripStatuses.active : TripStatuses.all)
            _chip(
              _statusLabel(t, status),
              _statusFilter == status,
              () => setState(() => _statusFilter = status),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );

  Widget _buildBody(AppTexts t) {
    if (_loading && _trips.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _trips.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: Text(t.tryAgain)),
            ],
          ),
        ),
      );
    }
    final items = _filtered;
    if (items.isEmpty) return Center(child: Text(t.noTrips));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _buildTile(t, items[i]),
      ),
    );
  }

  Widget _buildTile(AppTexts t, Trip trip) {
    final color = _statusColor(trip.status);
    final totalStops = trip.allStops.length;
    return ListTile(
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withAlpha(38),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          trip.routeNumber ?? '??',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ),
      title: Text(
        trip.direction,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🚌 ${trip.busNumber ?? '—'}'
            '${trip.busLicensePlate != null ? ' · ${trip.busLicensePlate}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          Row(
            children: [
              Text(
                _statusLabel(t, trip.status),
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (totalStops > 0) ...[
                const Text(' · ', style: TextStyle(fontSize: 11)),
                Text(
                  t.stopProgress(trip.currentStopIndex, totalStops),
                  style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ],
            ],
          ),
          // `driver` is only stamped when a driver STARTS the trip, so a
          // scheduled trip shows its bus's assigned driver instead — that's the
          // only link that exists at this point.
          if (trip.driverId == null && trip.busAssignedDriverId == null)
            Text(
              t.noDriverYet,
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (action) {
          if (action == 'status') _changeStatus(trip);
          if (action == 'delete') _delete(trip);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'status',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz, size: 20),
              title: Text(t.changeStatus),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete, size: 20, color: Colors.red),
              title: Text(
                t.delete,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

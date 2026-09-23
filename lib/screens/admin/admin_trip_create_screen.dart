import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/admin_route.dart';
import '../../models/bus.dart';
import '../../models/trip.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';

/// Schedule a trip: pick a route, pick a bus, post.
///
/// The backend seeds the new trip at stop index 0 with the first stop's
/// coordinates, so it appears on rider maps immediately as a parked bus.
class AdminTripCreateScreen extends StatefulWidget {
  const AdminTripCreateScreen({super.key});

  @override
  State<AdminTripCreateScreen> createState() => _AdminTripCreateScreenState();
}

class _AdminTripCreateScreenState extends State<AdminTripCreateScreen> {
  final AdminService _service = AdminService();

  List<AdminRoute> _routes = const [];
  List<Bus> _buses = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? _routeId;
  String? _busId;
  String _status = TripStatuses.scheduled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.fetchAllRoutes(),
        _service.fetchBuses(),
      ]);
      if (!mounted) return;
      final routes = (results[0] as List<AdminRoute>)
          .where((r) => r.status == 'active')
          // A route with no stops can't host a trip — the backend rejects it
          // with 400. Routes whose stop count the API didn't report are kept:
          // filtering on an absent count could empty the picker entirely.
          .where((r) => r.stopCount == null || r.stopCount! > 0)
          .toList();
      final buses = (results[1] as List<Bus>)
          .where((b) => b.isInService)
          .toList();
      setState(() {
        _routes = routes;
        _buses = buses;
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

  Future<void> _save() async {
    final t = context.read<SettingsProvider>().t;
    if (_routeId == null) {
      _snack(t.routeRequired);
      return;
    }
    if (_busId == null) {
      _snack(t.busRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.createTrip(
        routeId: _routeId!,
        busId: _busId!,
        status: _status,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final message = e is AdminApiException ? e.message : e.toString();
      setState(() {
        _saving = false;
        // The one error worth translating — it tells the admin exactly what to
        // go fix, and the raw string is backend-speak.
        _error = message.contains('no stops') ? t.routeHasNoStops : message;
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _routeLabel(AdminRoute r) {
    final parts = [
      if (r.code != null && r.code!.isNotEmpty) r.code!,
      r.name ?? r.id,
    ];
    return parts.join(' · ');
  }

  String _statusLabel(AppTexts t, String status) => switch (status) {
        TripStatuses.scheduled => t.tripStatusScheduled,
        TripStatuses.inProgress => t.tripStatusInProgress,
        TripStatuses.completed => t.tripStatusCompleted,
        TripStatuses.cancelled => t.tripStatusCancelled,
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.createTrip),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _routeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.routeField,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final r in _routes)
                      DropdownMenuItem(
                        value: r.id,
                        child: Text(
                          _routeLabel(r),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged:
                      _saving ? null : (v) => setState(() => _routeId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _busId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.busField,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final b in _buses)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          '${b.busNumber} · ${b.licensePlate}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _busId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: InputDecoration(
                    labelText: t.statusField,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in TripStatuses.active)
                      DropdownMenuItem(
                        value: s,
                        child: Text(_statusLabel(t, s)),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(
                            () => _status = v ?? TripStatuses.scheduled,
                          ),
                ),
                if (_routes.isEmpty || _buses.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _routes.isEmpty ? t.routeHasNoStops : t.noBuses,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(t.create),
                ),
              ],
            ),
    );
  }
}

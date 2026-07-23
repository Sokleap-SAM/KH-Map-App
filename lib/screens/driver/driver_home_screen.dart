import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/route_stop.dart';
import '../../providers/driver_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/constants/colors.dart';
import 'driver_trip_detail_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final MapController _mapController = MapController();
  List<RouteStop> _stops = const [];
  String? _stopsForTripId;
  LatLng? _selfLocation;
  StreamSubscription<Position>? _selfSub;

  @override
  void initState() {
    super.initState();
    _selfSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5,
          ),
        ).listen((p) {
          if (!mounted) return;
          setState(() => _selfLocation = LatLng(p.latitude, p.longitude));
        });
  }

  @override
  void dispose() {
    _selfSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureStops(DriverProvider d) async {
    final tripId = d.activeTrip?.id;
    if (tripId == null) {
      _stopsForTripId = null;
      if (_stops.isNotEmpty && mounted) setState(() => _stops = const []);
      return;
    }
    if (_stopsForTripId == tripId) return;
    _stopsForTripId = tripId;
    final stops = await d.fetchActiveRouteStops();
    if (!mounted) return;
    setState(() => _stops = stops.cast<RouteStop>());
  }

  List<LatLng> _polyline() {
    final out = <LatLng>[];
    for (final s in _stops) {
      if (s.segmentPath != null && s.segmentPath!.isNotEmpty) {
        out.addAll(s.segmentPath!);
      } else {
        out.add(s.location);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DriverProvider>();
    // Defer stop-loading to after this frame: _ensureStops may call setState,
    // which is illegal during build().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureStops(d);
    });
    final inTrip = d.shiftState == DriverShiftState.onShiftInTrip;
    final online = d.shiftState != DriverShiftState.offShift;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(context.watch<SettingsProvider>().t.driverTitle),
        actions: [
          _StatusPill(online: online),
          const SizedBox(width: 8),
          Switch(
            value: online,
            onChanged: d.busy ? null : (v) => d.setShift(v),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _selfLocation ?? const LatLng(11.5564, 104.9282),
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'kh_map_app',
              ),
              if (inTrip && _polyline().length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polyline(),
                      color: Colors.blueAccent,
                      strokeWidth: 5,
                    ),
                  ],
                ),
              if (inTrip)
                MarkerLayer(
                  markers: [
                    for (final s in _stops)
                      Marker(
                        point: s.location,
                        width: 20,
                        height: 20,
                        child: const Icon(
                          Icons.circle,
                          size: 12,
                          color: Colors.blue,
                        ),
                      ),
                  ],
                ),
              if (_selfLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selfLocation!,
                      width: 30,
                      height: 30,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (d.lastError != null)
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Material(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    d.lastError!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (inTrip && d.activeTrip != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ActiveTripSheet(trip: d.activeTrip!),
            ),
          if (!d.hasLocationPermission)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: () =>
                      context.read<DriverProvider>().checkLocationPermission(),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Location permission is required to start a trip. Tap to grant.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool online;
  const _StatusPill({required this.online});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade600 : Colors.grey.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        online ? 'Online' : 'Offline',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ActiveTripSheet extends StatelessWidget {
  final dynamic trip;
  const _ActiveTripSheet({required this.trip});

  @override
  Widget build(BuildContext context) {
    final d = context.read<DriverProvider>();
    final t = context.watch<SettingsProvider>().t;
    final routeNumber = trip.routeNumber ?? '';
    final routeName = trip.routeName ?? '';
    final nextStop = trip.nextStopName ?? '';

    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriverTripDetailScreen(tripId: trip.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$routeNumber  $routeName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(t.nextStopColon(nextStop)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: d.busy ? null : () => d.cancelTrip(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    t.cancelTrip,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

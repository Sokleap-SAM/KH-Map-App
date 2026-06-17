import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/admin_route.dart';
import '../../models/route_stop.dart';
import '../../services/admin_service.dart';
import '../../services/transit_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_route_create_screen.dart';

/// Route detail: shows the road-snapped polyline (decoded from each stop's
/// `segmentPath`) and the ordered stop list with edit/delete/append actions.
///
/// Pops `true` if anything changed so the list screen refreshes.
class AdminRouteDetailScreen extends StatefulWidget {
  final String routeId;
  final AdminRoute summary;

  const AdminRouteDetailScreen({
    super.key,
    required this.routeId,
    required this.summary,
  });

  @override
  State<AdminRouteDetailScreen> createState() => _AdminRouteDetailScreenState();
}

class _AdminRouteDetailScreenState extends State<AdminRouteDetailScreen> {
  final TransitService _transit = TransitService();
  final AdminService _admin = AdminService();
  final MapController _mapController = MapController();

  List<RouteStop> _stops = const [];
  bool _loading = true;
  bool _dirty = false; // did we change anything to report back?
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops() async {
    if (mounted) setState(() => _loading = true);
    try {
      final stops = await _transit.fetchRouteStops(widget.routeId)
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      if (!mounted) return;
      setState(() {
        _stops = stops;
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

  LatLng get _center =>
      _stops.isNotEmpty ? _stops.first.location : const LatLng(11.5564, 104.9282);

  Future<void> _append() async {
    final routeId = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => AdminRouteCreateScreen(
          appendRouteId: widget.routeId,
          appendRouteLabel: widget.summary.code ?? widget.summary.name,
          existingStops: _stops,
        ),
      ),
    );
    if (routeId != null) {
      _dirty = true;
      _loadStops();
    }
  }

  Future<void> _deleteStop(RouteStop stop) async {
    final ok = await _confirm(
      title: 'លុបចំណត?',
      message: 'លុប "${stop.stopName}" ចេញពីផ្លូវ?',
    );
    if (ok != true) return;
    try {
      await _admin.deleteRouteStop(stop.id);
      _dirty = true;
      await _loadStops();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  Future<void> _deleteRoute() async {
    final ok = await _confirm(
      title: 'លុបផ្លូវទាំងមូល?',
      message: 'លុបផ្លូវ "${widget.summary.code ?? widget.summary.name}" '
          'និងចំណតទាំងអស់? សកម្មភាពនេះមិនអាចត្រឡប់វិញបានទេ។',
    );
    if (ok != true) return;
    try {
      await _admin.deleteRoute(widget.routeId);
      if (!mounted) return;
      Navigator.of(context).pop(true); // route gone → refresh list
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('បោះបង់'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('លុប', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final title = [
      if (s.code != null && s.code!.isNotEmpty) s.code,
      s.name ?? 'Route',
    ].join('  ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.delete_forever),
              tooltip: 'លុបផ្លូវ',
              onPressed: _deleteRoute,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'admin_route_detail_fab',
          backgroundColor: AppColors.secondaryColor,
          foregroundColor: Colors.white,
          onPressed: _append,
          icon: const Icon(Icons.add_location_alt),
          label: const Text('បន្ថែមចំណត'),
        ),
        body: _loading && _stops.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  SizedBox(height: 240, child: _buildMap()),
                  Expanded(child: _buildStopList()),
                ],
              ),
      ),
    );
  }

  Widget _buildMap() {
    final line = _polyline();
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _center, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        if (line.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: line,
                color: AppColors.primaryColor,
                strokeWidth: 5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final s in _stops)
              Marker(
                point: s.location,
                width: 18,
                height: 18,
                child: const Icon(Icons.circle, size: 12, color: Colors.blue),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStopList() {
    if (_error != null && _stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_stops.isEmpty) {
      return const Center(child: Text('មិនទាន់មានចំណត'));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _stops.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final stop = _stops[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primaryColor,
            child: Text(
              '${stop.stopOrder}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          title: Text(stop.stopName),
          subtitle: Text(
            '${stop.location.latitude.toStringAsFixed(5)}, '
            '${stop.location.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
            onPressed: () => _deleteStop(stop),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/admin_route.dart';
import '../../models/route_stop.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../services/transit_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import 'admin_color_picker.dart';
import 'admin_map_size_button.dart';
import 'admin_place_request_history_screen.dart';
import 'admin_route_create_screen.dart';
import 'admin_route_detail_screen.dart';

/// Admin route list. Columns per the brief: name, code, isLine, status,
/// stop count. An overview map at the top draws every route's road-snapped
/// polyline (same geometry the rider sees), colored from the route's own
/// `color` field. FAB opens the map-driven create flow.
class AdminRoutesScreen extends StatefulWidget {
  const AdminRoutesScreen({super.key});

  @override
  State<AdminRoutesScreen> createState() => _AdminRoutesScreenState();
}

class _AdminRoutesScreenState extends State<AdminRoutesScreen> {
  final AdminService _service = AdminService();
  final TransitService _transit = TransitService();
  final MapController _mapController = MapController();

  AppTexts get _t => context.read<SettingsProvider>().t;

  List<AdminRoute> _routes = const [];
  // routeId → road-snapped polyline points (rider-facing geometry).
  final Map<String, List<LatLng>> _geometry = {};
  // routeId → ordered stops, for drawing bus-stop markers.
  final Map<String, List<RouteStop>> _routeStops = {};
  bool _loading = true;
  String? _error;
  String _filter = '';
  String? _selectedId;
  double _zoom = 12;

  // Resizable map "banner": fraction of body height (50% → 30% → 10%).
  static const List<double> _mapSizes = [0.5, 0.3, 0.1];
  double _mapFraction = 0.3;

  Color _colorFor(String routeId) {
    final i = _routes.indexWhere((r) => r.id == routeId);
    // Routes carry their own `color`; fall back to a neutral default.
    if (i >= 0) {
      final c = routeColorFromHex(_routes[i].color);
      if (c != null) return c;
    }
    return AppColors.primaryColor;
  }

  void _cycleMapSize() {
    final i = _mapSizes.indexOf(_mapFraction);
    setState(() => _mapFraction = _mapSizes[(i + 1) % _mapSizes.length]);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final routes = await _service.fetchAllRoutes();
      if (!mounted) return;
      setState(() {
        _routes = routes;
        _error = null;
        _loading = false;
      });
      _loadGeometry(routes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  /// Pulls each route's stops and builds its polyline. Fetched concurrently;
  /// a failure on one route just leaves that route without a line.
  Future<void> _loadGeometry(List<AdminRoute> routes) async {
    await Future.wait(
      routes.map((r) async {
        try {
          final stops = await _transit.fetchRouteStops(r.id)
            ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
          if (!mounted) return;
          setState(() {
            _geometry[r.id] = _buildRoutePath(stops);
            _routeStops[r.id] = stops;
          });
        } catch (_) {
          // Leave this route without geometry; the list row still shows.
        }
      }),
    );
  }

  List<LatLng> _buildRoutePath(List<RouteStop> stops) {
    final points = <LatLng>[];
    for (final stop in stops) {
      if (stop.segmentPath != null && stop.segmentPath!.isNotEmpty) {
        if (points.isNotEmpty) points.removeLast();
        points.addAll(stop.segmentPath!);
      } else {
        points.add(stop.location);
      }
    }
    return points;
  }

  List<AdminRoute> get _filtered {
    if (_filter.isEmpty) return _routes;
    final q = _filter.toLowerCase();
    return _routes.where((r) {
      final name = (r.name ?? '').toLowerCase();
      final code = (r.code ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  Future<void> _openCreate() async {
    final newRouteId = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const AdminRouteCreateScreen()),
    );
    if (newRouteId == null) return;
    await _load();
    // Land on the new route's detail, per the brief.
    if (!mounted) return;
    AdminRoute? match;
    for (final r in _routes) {
      if (r.id == newRouteId) {
        match = r;
        break;
      }
    }
    if (match != null) _openDetail(match);
  }

  Future<void> _toggleStatus(AdminRoute r) async {
    final next = r.status == 'active' ? 'inactive' : 'active';
    try {
      await AdminService().setRouteStatus(r.id, next);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.statusArrow(next))));
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_t.failedWith(msg))));
    }
  }

  Future<void> _openDetail(AdminRoute r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminRouteDetailScreen(routeId: r.id, summary: r),
      ),
    );
    if (changed == true) _load();
  }

  /// Center the overview map on a route and mark it selected (drawn thicker).
  void _focusRoute(AdminRoute r) {
    final pts = _geometry[r.id];
    setState(() => _selectedId = r.id);
    if (pts != null && pts.isNotEmpty) {
      _mapController.move(pts.first, 13);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'draft':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.manageRoutes),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: t.history,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminPlaceRequestHistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_routes_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        icon: const Icon(Icons.add_location_alt),
        label: Text(t.newRoute),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _routes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _load,
                child: Text(t.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final mapHeight = constraints.maxHeight * _mapFraction;
        return Column(
          children: [
            SizedBox(
              height: mapHeight,
              child: Stack(
                children: [
                  _buildOverviewMap(),
                  MapSizeButton(fraction: _mapFraction, onTap: _cycleMapSize),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t.searchByNameCode,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            Expanded(child: _buildList(t)),
          ],
        );
      },
    );
  }

  Widget _buildOverviewMap() {
    // Draw only the routes currently visible in the (possibly filtered) list.
    final visible = _filtered;
    LatLng? center;
    for (final r in visible) {
      final pts = _geometry[r.id];
      if (pts != null && pts.isNotEmpty) {
        center = pts.first;
        break;
      }
    }
    center ??= const LatLng(11.5564, 104.9282);

    final polylines = <Polyline>[];
    final markers = <Marker>[];
    for (final r in visible) {
      final pts = _geometry[r.id];
      final selected = r.id == _selectedId;
      if (pts != null && pts.length >= 2) {
        polylines.add(
          Polyline(
            points: pts,
            color: _colorFor(r.id).withValues(alpha: selected ? 1.0 : 0.75),
            strokeWidth: selected ? 6 : 4,
          ),
        );
      }
      // Zoom-based stop display, mirroring the rider map: hide stops when far,
      // tiny dot mid-zoom, full bus-stop icon when close.
      if (_zoom > 12.0) {
        final zoomedIn = _zoom >= 15.0;
        final stopSize = zoomedIn ? 20.0 : 6.0;
        for (final s in _routeStops[r.id] ?? const <RouteStop>[]) {
          markers.add(
            Marker(
              point: s.location,
              width: stopSize,
              height: stopSize,
              alignment: Alignment.center,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: zoomedIn ? 2 : 1,
                  ),
                ),
                child: zoomedIn
                    ? const Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: 10,
                      )
                    : null,
              ),
            ),
          );
        }
      }
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
        onPositionChanged: (camera, _) {
          if ((camera.zoom - _zoom).abs() >= 0.5) {
            setState(() => _zoom = camera.zoom);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildList(AppTexts t) {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(child: Text(t.noRoutesYet));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = items[i];
          final title = [
            if (r.code != null && r.code!.isNotEmpty) r.code,
            r.name ?? t.noName,
          ].join('  ');
          // GET /transit/routes carries no stop count; derive it from the
          // stops we fetched for the polyline (null while still loading).
          final count = _routeStops[r.id]?.length ?? r.stopCount;
          return ListTile(
            selected: r.id == _selectedId,
            selectedTileColor: _colorFor(r.id).withValues(alpha: 0.08),
            leading: Icon(
              r.isLine ? Icons.loop : Icons.linear_scale,
              color: _colorFor(r.id),
            ),
            title: Text(title),
            subtitle: Text(
              '${t.adminRouteType(r.isLine, r.direction)} · '
              '${count != null ? t.stopsCount(count) : t.stopsCountUnknown}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.center_focus_strong, size: 20),
                  tooltip: t.showOnMap,
                  onPressed: () => _focusRoute(r),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toggleStatus(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(r.status),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          r.status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.swap_horiz,
                          color: Colors.white,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            onTap: () => _openDetail(r),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_map_size_button.dart';
import 'admin_place_requests_screen.dart';
import 'admin_stop_edit_screen.dart';

/// Stops tab — CRUD over /places. An overview map at the top shows every stop;
/// the list below carries name, coords, and a lazily-loaded "used in N routes"
/// count. Delete surfaces the referencing routes when the stop is in use.
class AdminStopsScreen extends StatefulWidget {
  const AdminStopsScreen({super.key});

  @override
  State<AdminStopsScreen> createState() => _AdminStopsScreenState();
}

class _AdminStopsScreenState extends State<AdminStopsScreen> {
  final AdminService _service = AdminService();
  final MapController _mapController = MapController();

  List<Place> _places = const [];
  bool _loading = true;
  String? _error;
  String _filter = '';
  LatLng? _selected;

  // Count of user-submitted places awaiting review — drives the bell badge.
  int _pendingCount = 0;

  // Resizable map "banner": fraction of body height (60% → 30% → 10%).
  static const List<double> _mapSizes = [0.6, 0.3, 0.1];
  double _mapFraction = 0.3;

  void _cycleMapSize() {
    final i = _mapSizes.indexOf(_mapFraction);
    setState(() => _mapFraction = _mapSizes[(i + 1) % _mapSizes.length]);
  }

  // Cache usage lookups so each row only fetches once.
  final Map<String, Future<StopUsage>> _usageCache = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadPendingCount();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final places = await _service.fetchPlaces();
      if (!mounted) return;
      setState(() {
        _places = places;
        _usageCache.clear();
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

  /// Refreshes the pending-request badge count. Best-effort and silent.
  Future<void> _loadPendingCount() async {
    try {
      final requests = await _service.fetchPendingPlaceRequests();
      if (!mounted) return;
      setState(() => _pendingCount = requests.length);
    } catch (_) {/* leave the previous count */}
  }

  /// Opens the request review queue, then refreshes the badge and — since an
  /// approval publishes a new place — the stop list/map too.
  Future<void> _openRequests() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AdminPlaceRequestsScreen()),
    );
    if (!mounted) return;
    _loadPendingCount();
    _load();
  }

  Future<StopUsage> _usage(String placeId) =>
      _usageCache[placeId] ??= _service.fetchStopRoutes(placeId);

  List<Place> get _filtered {
    if (_filter.isEmpty) return _places;
    final q = _filter.toLowerCase();
    return _places.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminStopEditScreen()),
    );
    if (ok == true) _load();
  }

  Future<void> _edit(Place p) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminStopEditScreen(existing: p)),
    );
    if (ok == true) _load();
  }

  Future<void> _delete(Place p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('លុបចំណត?'),
        content: Text('លុប "${p.name}"?'),
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
    if (confirm != true) return;
    try {
      await _service.deletePlace(p.id);
      _usageCache.remove(p.id);
      _load();
    } on AdminApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 || e.statusCode == 400) {
        await _showInUse(p);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('បរាជ័យ: ${e.message}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('បរាជ័យ: $e')));
    }
  }

  /// Stop is referenced by routes — show which ones.
  Future<void> _showInUse(Place p) async {
    StopUsage? usage;
    try {
      usage = await _service.fetchStopRoutes(p.id);
    } catch (_) {}
    if (!mounted) return;
    final routes = usage?.routes ?? const [];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('មិនអាចលុបបានទេ (In use)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${p.name}" ត្រូវបានប្រើនៅក្នុង ${usage?.count ?? routes.length} ផ្លូវ៖'),
            const SizedBox(height: 8),
            if (routes.isEmpty)
              const Text('—')
            else
              ...routes.map((r) => Text(
                    '• ${[
                      if (r.code != null && r.code!.isNotEmpty) r.code,
                      r.name ?? r.id,
                    ].join('  ')}',
                  )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('យល់ព្រម'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('គ្រប់គ្រងចំណត (Stops)'),
        actions: [
          IconButton(
            tooltip: 'សំណើទីកន្លែង',
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              backgroundColor: AppColors.alertBorderColor,
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: _openRequests,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading
                ? null
                : () {
                    _load();
                    _loadPendingCount();
                  },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_stops_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add_location_alt),
        label: const Text('បង្កើតចំណត'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _places.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _places.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('ព្យាយាមម្ដងទៀត')),
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
                  MapSizeButton(
                    fraction: _mapFraction,
                    onTap: _cycleMapSize,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ស្វែងរកតាមឈ្មោះ (Filter by name)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            Expanded(child: _buildList()),
          ],
        );
      },
    );
  }

  Widget _buildOverviewMap() {
    final center = _selected ??
        (_places.isNotEmpty
            ? LatLng(_places.first.latitude, _places.first.longitude)
            : const LatLng(11.5564, 104.9282));
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        MarkerLayer(
          markers: [
            for (final p in _places)
              Marker(
                point: LatLng(p.latitude, p.longitude),
                width: 18,
                height: 18,
                child: Icon(
                  Icons.circle,
                  size: _selected == LatLng(p.latitude, p.longitude) ? 16 : 11,
                  color: _selected == LatLng(p.latitude, p.longitude)
                      ? Colors.red
                      : AppColors.primaryColor,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildList() {
    final items = _filtered;
    if (items.isEmpty) {
      return const Center(child: Text('មិនមានចំណត'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = items[i];
          final loc = LatLng(p.latitude, p.longitude);
          return ListTile(
            leading: const Icon(Icons.place, color: AppColors.primaryColor),
            title: Text(p.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 11),
                ),
                _UsageLabel(future: _usage(p.id)),
              ],
            ),
            isThreeLine: true,
            onTap: () {
              setState(() => _selected = loc);
              _mapController.move(loc, 15);
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _edit(p),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _delete(p),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UsageLabel extends StatelessWidget {
  final Future<StopUsage> future;
  const _UsageLabel({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StopUsage>(
      future: future,
      builder: (context, snap) {
        String text;
        if (snap.connectionState != ConnectionState.done) {
          text = 'used in … routes';
        } else if (snap.hasError) {
          text = 'usage unavailable';
        } else {
          text = 'used in ${snap.data!.count} routes';
        }
        return Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        );
      },
    );
  }
}

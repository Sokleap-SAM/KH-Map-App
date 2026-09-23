import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/bus.dart';
import '../../models/trip.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../services/mqtt_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import 'admin_bus_edit_screen.dart';
import 'admin_map_size_button.dart';

/// Bus management — the fleet on a live map, plus driver assignment.
///
/// **A bus has no position of its own.** The `Bus` document carries no
/// coordinates; a bus is only locatable while it has an active trip, whose
/// position comes from Redis (via the HTTP snapshot) and then MQTT. So the map
/// plots active trips joined back to their bus, and a bus sitting idle in the
/// fleet simply isn't on it — the list is the complete inventory, the map is
/// only what's moving.
///
/// Assignment lives here rather than on the user screen because the constraint
/// being managed is "which bus is free": the endpoint is keyed by driver id, but
/// the decision is about the vehicle.
class AdminBusesScreen extends StatefulWidget {
  const AdminBusesScreen({super.key});

  @override
  State<AdminBusesScreen> createState() => _AdminBusesScreenState();
}

class _AdminBusesScreenState extends State<AdminBusesScreen> {
  final AdminService _service = AdminService();
  final MqttService _mqtt = MqttService.instance;
  final MapController _mapController = MapController();

  List<Bus> _buses = const [];
  List<AppUser> _drivers = const [];
  List<Trip> _activeTrips = const [];
  bool _loading = true;
  String? _error;
  String? _statusFilter;

  /// Client-side search, like the stop and route searches: `/transit/buses`
  /// takes no query parameters, and a fleet of tens filters instantly.
  String _search = '';

  // ── Map state ─────────────────────────────────────────────────────────────

  /// Resizable map "banner", matching the Places screen.
  static const List<double> _mapSizes = [0.8, 0.6, 0.3, 0.1];
  double _mapFraction = 0.3;
  double _zoom = 12;
  Bus? _selected;

  /// Live positions from MQTT, keyed by busId. Overrides the HTTP snapshot,
  /// which is up to a metadata-poll old.
  final Map<String, LatLng> _livePositions = {};

  /// routeId → unsubscribe callback, still resolving while the future is
  /// pending. Mirrors TransitProvider's bookkeeping.
  final Map<String, Future<VoidCallback>> _routeSubs = {};

  /// MQTT delivers ~1 message/sec per bus; repainting a map per message would
  /// burn frames for no visible gain. Positions accumulate and paint on a tick.
  Timer? _repaintThrottle;
  static const Duration _repaintInterval = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _repaintThrottle?.cancel();
    // Fire-and-forget: we're tearing down either way.
    for (final pending in _routeSubs.values) {
      pending.then((unsub) => unsub()).catchError((_) {});
    }
    _routeSubs.clear();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      // Drivers and active trips are both needed to render a row honestly:
      // who's driving it, whether it's safe to delete, and where it is.
      final results = await Future.wait([
        _service.fetchBuses(),
        _service.fetchUsers(role: UserRoles.driver, limit: 100),
        _service.fetchActiveTrips(),
      ]);
      if (!mounted) return;
      final trips = results[2] as List<Trip>;
      setState(() {
        _buses = results[0] as List<Bus>;
        _drivers = (results[1] as UserPage).data;
        _activeTrips = trips;
        // Drop positions for buses that no longer have an active trip, so a
        // finished trip's last-known point can't linger on the map.
        final liveBusIds = trips.map((t) => t.busId).toSet();
        _livePositions.removeWhere((busId, _) => !liveBusIds.contains(busId));
        // Re-resolve the selection against the fresh list; drops it if deleted.
        Bus? sel;
        for (final b in _buses) {
          if (b.id == _selected?.id) sel = b;
        }
        _selected = sel;
        _error = null;
        _loading = false;
      });
      _syncSubscriptions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  // ── Live positions ────────────────────────────────────────────────────────

  /// Subscribe to the routes the active trips run on, and drop the rest.
  ///
  /// Per-route topics are all MQTT offers — there's no per-bus topic — so we
  /// subscribe by route and filter incoming messages down to the buses we care
  /// about.
  Future<void> _syncSubscriptions() async {
    final wanted = _activeTrips
        .map((t) => t.routeId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final current = _routeSubs.keys.toSet();

    for (final id in current.difference(wanted)) {
      final pending = _routeSubs.remove(id);
      if (pending == null) continue;
      try {
        (await pending)();
      } catch (_) {
        // best-effort unsubscribe
      }
    }
    for (final id in wanted.difference(current)) {
      _routeSubs[id] = _mqtt.subscribeToRoute(id, _handlePosition);
    }
  }

  void _handlePosition(BusPosition pos) {
    if (!mounted) return;
    _livePositions[pos.busId] = pos.location;
    // Coalesce the burst into one repaint.
    if (_repaintThrottle?.isActive ?? false) return;
    _repaintThrottle = Timer(_repaintInterval, () {
      if (mounted) setState(() {});
    });
  }

  /// Where to draw [bus]: the freshest live fix, else the trip's HTTP snapshot,
  /// else nowhere (no active trip, or no position reported yet).
  LatLng? _locationFor(Bus bus) {
    final live = _livePositions[bus.id];
    if (live != null) return live;
    return _activeTripFor(bus)?.currentLocation;
  }

  Trip? _activeTripFor(Bus bus) {
    for (final t in _activeTrips) {
      if (t.busId == bus.id) return t;
    }
    return null;
  }

  /// Buses in the current filter that actually have somewhere to be drawn.
  List<Bus> get _mappable =>
      _filtered.where((b) => _locationFor(b) != null).toList();

  // ── Data helpers ──────────────────────────────────────────────────────────

  /// Status chip AND search, applied together. Drives both the list and the
  /// map, so a search narrows the markers too.
  List<Bus> get _filtered {
    final q = _search.trim().toLowerCase();
    return _buses.where((b) {
      if (_statusFilter != null && b.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      // The assigned driver is matched too — "which bus is Sok on" is a
      // question this screen gets asked, and the list already shows the name.
      final driver = _driverFor(b);
      return b.busNumber.toLowerCase().contains(q) ||
          b.licensePlate.toLowerCase().contains(q) ||
          (driver?.name.toLowerCase().contains(q) ?? false) ||
          (driver?.email.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  AppUser? _driverFor(Bus bus) {
    if (!bus.isAssigned) return null;
    for (final d in _drivers) {
      if (d.id == bus.assignedDriverId) return d;
    }
    return null;
  }

  int _activeTripCount(Bus bus) =>
      _activeTrips.where((t) => t.busId == bus.id).length;

  void _select(Bus bus) {
    final point = _locationFor(bus);
    setState(() => _selected = bus);
    if (point != null) {
      _mapController.move(point, _zoom < 15 ? 15 : _zoom);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminBusEditScreen()),
    );
    if (saved == true && mounted) {
      _snack(context.read<SettingsProvider>().t.busCreated);
      _load();
    }
  }

  Future<void> _edit(Bus bus) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminBusEditScreen(existing: bus)),
    );
    if (saved == true && mounted) {
      _snack(context.read<SettingsProvider>().t.busUpdated);
      _load();
    }
  }

  /// Assign or change this bus's driver.
  ///
  /// Only unassigned drivers are offered: the backend refuses to move a bus
  /// between drivers implicitly (409), so a picker full of already-assigned
  /// drivers would be a list of guaranteed failures.
  Future<void> _assignDriver(Bus bus) async {
    final t = context.read<SettingsProvider>().t;
    final free = _drivers.where((d) => !d.hasAssignedBus).toList();

    if (free.isEmpty) {
      _snack(t.noDriversAvailable);
      return;
    }

    final picked = await showDialog<AppUser>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.assignDriver),
        children: [
          for (final d in free)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(d.name.isEmpty ? d.email : d.name),
              subtitle: Text(d.email, style: const TextStyle(fontSize: 11)),
              onTap: () => Navigator.of(ctx).pop(d),
            ),
        ],
      ),
    );
    if (picked == null) return;

    try {
      await _service.assignDriverBus(picked.id, bus.id);
      if (!mounted) return;
      _snack(t.driverAssigned);
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      // 409 is the "already assigned" case, which has a clearer phrasing than
      // the backend's raw sentence.
      _snack(
        e is AdminApiException && e.statusCode == 409
            ? t.busAlreadyAssigned
            : t.failedWith(msg),
      );
    }
  }

  /// Unassign — the backend also forces the driver's shift status to `off`.
  Future<void> _unassignDriver(Bus bus) async {
    final t = context.read<SettingsProvider>().t;
    final driverId = bus.assignedDriverId;
    if (driverId == null) return;
    try {
      await _service.assignDriverBus(driverId, null);
      if (!mounted) return;
      _snack(t.driverUnassigned);
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(t.failedWith(e is AdminApiException ? e.message : e.toString()));
    }
  }

  /// Delete, with the two guards the backend doesn't have.
  ///
  /// Deleting a bus server-side is unconditional: it won't stop you orphaning
  /// active trips or leaving `User.assignedBusId` pointing at nothing. So both
  /// checks happen here.
  Future<void> _delete(Bus bus) async {
    final t = context.read<SettingsProvider>().t;

    final tripCount = _activeTripCount(bus);
    if (tripCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t.busInUseTitle),
          content: Text(t.busInUseBody(tripCount)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.close),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deleteBusTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${bus.busNumber} · ${bus.licensePlate}'),
            const SizedBox(height: 8),
            if (bus.isAssigned)
              Text(
                t.busHasDriverWarning,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              )
            else
              Text(
                t.preferOutOfService,
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
      await _service.deleteBus(bus.id);
      if (!mounted) return;
      _snack(t.busDeleted);
      _load();
    } catch (e) {
      if (!mounted) return;
      _snack(t.failedWith(e is AdminApiException ? e.message : e.toString()));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── Labels ────────────────────────────────────────────────────────────────

  String _statusLabel(AppTexts t, String status) => switch (status) {
        BusStatuses.inService => t.busStatusInService,
        BusStatuses.outOfService => t.busStatusOutOfService,
        BusStatuses.maintenance => t.busStatusMaintenance,
        _ => status,
      };

  Color _statusColor(String status) => switch (status) {
        BusStatuses.inService => Colors.green,
        BusStatuses.outOfService => Colors.blueGrey,
        BusStatuses.maintenance => Colors.orange,
        _ => Colors.grey,
      };

  String _driverLabel(AppTexts t, Bus bus) {
    if (!bus.isAssigned) return t.unassigned;
    final driver = _driverFor(bus);
    // An assigned driver we can't resolve to a name still shows as assigned —
    // the id is proof enough, and claiming "unassigned" would be wrong.
    if (driver == null) return '—';
    return driver.name.isNotEmpty ? driver.name : driver.email;
  }

  void _cycleMapSize() {
    final i = _mapSizes.indexOf(_mapFraction);
    setState(() => _mapFraction = _mapSizes[(i + 1) % _mapSizes.length]);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.manageBuses),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin_buses_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(t.newBus),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppTexts t) {
    if (_loading && _buses.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _buses.isEmpty) {
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            SizedBox(
              height: constraints.maxHeight * _mapFraction,
              child: Stack(
                children: [
                  _buildMap(),
                  MapSizeButton(fraction: _mapFraction, onTap: _cycleMapSize),
                  _buildOnMapCount(t),
                  // Hide the card when a search or chip filters the selected
                  // bus out — its marker is gone, so the card shouldn't stay.
                  if (_selected != null &&
                      _filtered.any((b) => b.id == _selected!.id))
                    _buildSelectedCard(t, _selected!),
                ],
              ),
            ),
            _buildFilters(t),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t.searchBusesHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(child: _buildList(t)),
          ],
        );
      },
    );
  }

  Widget _buildMap() {
    final visible = _mappable;
    final center = _selected != null
        ? _locationFor(_selected!)
        : (visible.isNotEmpty ? _locationFor(visible.first) : null);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // Phnom Penh, for an empty fleet or a map with nothing moving.
        initialCenter: center ?? const LatLng(11.5564, 104.9282),
        initialZoom: 12,
        onTap: (_, _) => setState(() => _selected = null),
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
        MarkerLayer(
          markers: [
            for (final bus in visible)
              () {
                final point = _locationFor(bus)!;
                final selected = _selected?.id == bus.id;
                final trip = _activeTripFor(bus);
                // Colour by TRIP state — on this map every bus is moving, so
                // "is it running or parked" is the useful distinction, not the
                // fleet status already shown in the list.
                final color = trip?.isInProgress == true
                    ? Colors.green
                    : Colors.orange;
                final size = selected ? 40.0 : 30.0;
                return Marker(
                  point: point,
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(bus),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? Colors.red : color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                      child: Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                        size: size * 0.55,
                      ),
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }

  /// "N of M on the map" — without it, a fleet of 20 showing 3 markers reads as
  /// a broken map rather than 17 buses with no active trip.
  Widget _buildOnMapCount(AppTexts t) {
    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          t.busesOnMap(_mappable.length, _filtered.length),
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
    );
  }

  /// Action card shown over the map when a bus marker is tapped.
  Widget _buildSelectedCard(AppTexts t, Bus bus) {
    final trip = _activeTripFor(bus);
    return Positioned(
      left: 8,
      right: 8,
      bottom: 8,
      child: Card(
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.directions_bus,
                color: _statusColor(bus.status),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.busNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      [
                        _driverLabel(t, bus),
                        if (trip != null) '${trip.routeNumber} · ${trip.direction}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.edit,
                icon: const Icon(Icons.edit, color: AppColors.secondaryColor),
                onPressed: () => _edit(bus),
              ),
              IconButton(
                tooltip: bus.isAssigned ? t.unassignDriver : t.assignDriver,
                icon: Icon(
                  bus.isAssigned ? Icons.person_remove : Icons.person_add_alt,
                  color: AppColors.primaryColor,
                ),
                onPressed: () => bus.isAssigned
                    ? _unassignDriver(bus)
                    : _assignDriver(bus),
              ),
              IconButton(
                tooltip: t.delete,
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _delete(bus),
              ),
              IconButton(
                tooltip: t.close,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
        ),
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
          _chip(t.all, _statusFilter == null,
              () => setState(() => _statusFilter = null)),
          for (final s in BusStatuses.all)
            _chip(
              _statusLabel(t, s),
              _statusFilter == s,
              () => setState(() => _statusFilter = s),
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

  Widget _buildList(AppTexts t) {
    final items = _filtered;
    if (items.isEmpty) return Center(child: Text(t.noBuses));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => _buildTile(t, items[i]),
      ),
    );
  }

  Widget _buildTile(AppTexts t, Bus bus) {
    final color = _statusColor(bus.status);
    final tripCount = _activeTripCount(bus);
    final onMap = _locationFor(bus) != null;

    return ListTile(
      selected: _selected?.id == bus.id,
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withAlpha(38),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.directions_bus, color: color, size: 22),
      ),
      title: Text(bus.busNumber),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${bus.licensePlate} · ${bus.capacity} ${t.seats}',
            style: const TextStyle(fontSize: 11),
          ),
          Row(
            children: [
              Text(
                _statusLabel(t, bus.status),
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(' · ', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Text(
                  _driverLabel(t, bus),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: bus.isAssigned ? Colors.blueGrey : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          if (tripCount > 0)
            Text(
              t.busInUseBody(tripCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.green),
            ),
        ],
      ),
      isThreeLine: true,
      // Tapping a locatable bus frames it on the map; the rest go straight to
      // edit, since there's nothing to show them on.
      onTap: () => onMap ? _select(bus) : _edit(bus),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onMap)
            IconButton(
              tooltip: t.showOnMap,
              icon: const Icon(Icons.my_location, size: 18),
              onPressed: () => _select(bus),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  _edit(bus);
                case 'assign':
                  _assignDriver(bus);
                case 'unassign':
                  _unassignDriver(bus);
                case 'delete':
                  _delete(bus);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit, size: 20),
                  title: Text(t.edit),
                ),
              ),
              PopupMenuItem(
                value: bus.isAssigned ? 'unassign' : 'assign',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    bus.isAssigned
                        ? Icons.person_remove
                        : Icons.person_add_alt,
                    size: 20,
                  ),
                  title: Text(
                    bus.isAssigned ? t.unassignDriver : t.assignDriver,
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.delete, size: 20, color: Colors.red),
                  title: Text(
                    t.delete,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

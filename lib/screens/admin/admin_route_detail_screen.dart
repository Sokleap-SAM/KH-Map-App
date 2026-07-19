import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/admin_route.dart';
import '../../models/place.dart';
import '../../models/route_stop.dart';
import '../../services/admin_service.dart';
import '../../services/transit_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_color_picker.dart';
import 'admin_place_detail_screen.dart';
import 'admin_route_create_screen.dart';
import 'admin_route_edit_screen.dart';
import 'admin_segment_fix_screen.dart';

/// Route detail: shows the road-snapped segments (each stop's `segmentPath`,
/// drawn exactly as stored — stop coordinates are markers only, never part of
/// the line) and the ordered stop list with fix-road / change-place / delete /
/// append actions.
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

  // Mutable so an in-place metadata edit updates the title / polyline color.
  late AdminRoute _summary;

  // Multi-select for bulk delete. [_selected] holds route-stop ids.
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _bulkDeleting = false;
  int _bulkDone = 0;
  int _bulkTotal = 0;

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(RouteStop stop) {
    setState(() {
      if (!_selected.add(stop.id)) _selected.remove(stop.id);
    });
  }

  // Stop tapped on the map — shows the action card (name / view / edit /
  // delete). Cleared by tapping empty map, or re-resolved on reload.
  RouteStop? _mapSelected;

  /// Full place doc for a stop (photos, category). Null + snackbar on
  /// failure — opening the edit screen with partial data could wipe photos.
  Future<Place?> _fetchPlaceFor(RouteStop stop) async {
    try {
      return await _admin.fetchPlace(stop.stopId);
    } catch (e) {
      if (mounted) {
        final msg = e is AdminApiException ? e.message : e.toString();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
      }
      return null;
    }
  }

  Future<void> _viewStopPlace(RouteStop stop) async {
    final place = await _fetchPlaceFor(stop);
    if (place == null || !mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminPlaceDetailScreen(place: place)),
    );
    if (changed == true) {
      _dirty = true;
      await _loadStops();
    }
  }


  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    _loadStops();
  }

  Future<void> _editRoute() async {
    final updated = await Navigator.of(context).push<AdminRoute>(
      MaterialPageRoute(
        builder: (_) => AdminRouteEditScreen(route: _summary),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _summary = updated;
        _dirty = true;
      });
    }
  }

  Future<void> _loadStops() async {
    if (mounted) setState(() => _loading = true);
    try {
      final stops = await _transit.fetchRouteStops(widget.routeId)
        ..sort((a, b) => a.stopOrder.compareTo(b.stopOrder));
      if (!mounted) return;
      setState(() {
        _stops = stops;
        // Re-resolve the map selection against the fresh list; drops it if
        // the stop was deleted.
        RouteStop? sel;
        for (final s in stops) {
          if (s.id == _mapSelected?.id) {
            sel = s;
            break;
          }
        }
        _mapSelected = sel;
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

  /// One polyline per stored segment, rendered as-is. Legacy routes with no
  /// segment geometry at all fall back to a stop-to-stop line.
  List<List<LatLng>> _segmentLines() {
    final out = <List<LatLng>>[
      for (final s in _stops)
        if (s.segmentPath != null && s.segmentPath!.length >= 2)
          s.segmentPath!,
    ];
    if (out.isEmpty && _stops.length >= 2) {
      return [
        [for (final s in _stops) s.location],
      ];
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
          appendRouteLabel: _summary.code ?? _summary.name,
          existingStops: _stops,
        ),
      ),
    );
    if (routeId != null) {
      _dirty = true;
      _loadStops();
    }
  }

  /// Wrong road: steer the incoming segment (previous stop → this stop)
  /// through tapped via points. Only exists for stops with a predecessor.
  Future<void> _fixSegment(int index) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminSegmentFixScreen(
          stop: _stops[index],
          prevStop: _stops[index - 1],
          routeColor:
              routeColorFromHex(_summary.color) ?? AppColors.primaryColor,
        ),
      ),
    );
    if (ok == true) {
      _dirty = true;
      // Up to TWO segments changed (this one + the next) — re-fetch all.
      await _loadStops();
    }
  }

  /// Wrong place: swap the stop for another existing place. The backend
  /// recomputes BOTH adjacent segments.
  Future<void> _changePlace(RouteStop stop) async {
    final picked = await _pickPlace();
    if (picked == null || !mounted) return;
    final ok = await _confirm(
      title: 'ប្ដូរទីកន្លែង?',
      message: 'ប្ដូរ "${stop.stopName}" ទៅ "${picked.name}"?',
    );
    if (ok != true) return;
    try {
      await _admin.updateRouteStop(stop.id, placeId: picked.id);
      _dirty = true;
      await _loadStops();
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  /// Searchable bus-stop picker (bottom sheet). Returns the chosen place.
  Future<Place?> _pickPlace() async {
    List<Place>? places;
    try {
      places = await _admin.fetchPlaces();
    } catch (e) {
      if (mounted) {
        final msg = e is AdminApiException ? e.message : e.toString();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
      }
      return null;
    }
    if (!mounted) return null;
    final all = places;
    return showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = filter.toLowerCase();
            final items = q.isEmpty
                ? all
                : all.where((p) => p.name.toLowerCase().contains(q)).toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ស្វែងរកចំណត (Search stops)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setSheetState(() => filter = v),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('មិនមានចំណត'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = items[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.place,
                                  color: AppColors.primaryColor,
                                ),
                                title: Text(p.name),
                                subtitle: Text(
                                  '${p.latitude}, ${p.longitude}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onTap: () => Navigator.of(ctx).pop(p),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Deletes every selected stop, one DELETE per stop (there is no batch
  /// endpoint; each delete heals the chain server-side). Highest stopOrder
  /// first, and failures don't stop the rest — they're reported at the end.
  Future<void> _bulkDelete() async {
    if (_selected.isEmpty || _bulkDeleting) return;
    final targets = _stops.where((s) => _selected.contains(s.id)).toList()
      ..sort((a, b) => b.stopOrder.compareTo(a.stopOrder));
    final ok = await _confirm(
      title: 'លុបចំណត ${targets.length}?',
      message:
          'លុប ${targets.length} ចំណតចេញពីផ្លូវ? ផ្លូវនឹងត្រូវគណនាឡើងវិញ '
          '(segments recompute automatically).',
    );
    if (ok != true) return;
    setState(() {
      _bulkDeleting = true;
      _bulkDone = 0;
      _bulkTotal = targets.length;
    });
    final failed = <String>[];
    for (final s in targets) {
      try {
        await _admin.deleteRouteStop(s.id);
      } catch (_) {
        failed.add(s.stopName);
      }
      if (!mounted) return;
      setState(() => _bulkDone++);
    }
    _dirty = true;
    if (!mounted) return;
    setState(() {
      _bulkDeleting = false;
      _selecting = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? 'បានលុប ${targets.length} ចំណត (deleted)'
              : 'បានលុប ${targets.length - failed.length}, បរាជ័យ '
                    '${failed.length}: ${failed.join(', ')}',
        ),
      ),
    );
    await _loadStops();
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
      message: 'លុបផ្លូវ "${_summary.code ?? _summary.name}" '
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
    final s = _summary;
    final title = [
      if (s.code != null && s.code!.isNotEmpty) s.code,
      s.name ?? 'Route',
    ].join('  ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Back exits selection mode first; only then leaves the screen.
        if (_selecting) {
          if (!_bulkDeleting) _exitSelection();
          return;
        }
        Navigator.of(context).pop(_dirty);
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _bulkDeleting ? null : _exitSelection,
                ),
                title: Text('${_selected.length} បានជ្រើសរើស'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'ជ្រើសរើសទាំងអស់',
                    onPressed: _bulkDeleting
                        ? null
                        : () => setState(() {
                            if (_selected.length == _stops.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(_stops.map((s) => s.id));
                            }
                          }),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    tooltip: 'លុបចំណតដែលបានជ្រើសរើស',
                    onPressed: (_selected.isEmpty || _bulkDeleting)
                        ? null
                        : _bulkDelete,
                  ),
                ],
              )
            : AppBar(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                title: Text(title),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.checklist),
                    tooltip: 'ជ្រើសរើសច្រើន (Select stops)',
                    onPressed: _stops.isEmpty
                        ? null
                        : () => setState(() => _selecting = true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'កែផ្លូវ (Edit route)',
                    onPressed: _editRoute,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever),
                    tooltip: 'លុបផ្លូវ',
                    onPressed: _deleteRoute,
                  ),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
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
                  SizedBox(
                    height: 240,
                    child: Stack(
                      children: [
                        _buildMap(),
                        if (_mapSelected != null && !_selecting)
                          _buildStopCard(_mapSelected!),
                      ],
                    ),
                  ),
                  if (_bulkDeleting)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _bulkTotal == 0
                                  ? null
                                  : _bulkDone / _bulkTotal,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$_bulkDone / $_bulkTotal'),
                        ],
                      ),
                    ),
                  Expanded(child: _buildStopList()),
                ],
              ),
      ),
    );
  }

  Widget _buildMap() {
    final lines = _segmentLines();
    final color = routeColorFromHex(_summary.color) ?? AppColors.primaryColor;
    final dash = StrokePattern.dashed(segments: const [6, 5]);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 13,
        onTap: (_, _) => setState(() => _mapSelected = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        if (lines.isNotEmpty)
          PolylineLayer(
            polylines: [
              for (final line in lines)
                Polyline(points: line, color: color, strokeWidth: 5),
              // Stops sit on the sidewalk while the route runs on the road —
              // dashed connectors give the visual link (client-side only).
              for (final s in _stops)
                if (s.segmentPath != null && s.segmentPath!.isNotEmpty)
                  Polyline(
                    points: [s.segmentPath!.last, s.location],
                    color: Colors.blueGrey,
                    strokeWidth: 2,
                    pattern: dash,
                  ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final s in _stops)
              () {
                final selected = _mapSelected?.id == s.id;
                final size = selected ? 26.0 : 18.0;
                return Marker(
                  point: s.location,
                  width: size,
                  height: size,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // In bulk-select mode the map toggles the checkbox
                    // selection; otherwise it opens the action card.
                    onTap: () {
                      if (_selecting) {
                        if (!_bulkDeleting) _toggleSelected(s);
                      } else {
                        setState(() => _mapSelected = s);
                      }
                    },
                    child: Icon(
                      Icons.circle,
                      size: selected ? 20 : 12,
                      color: selected
                          ? Colors.red
                          : (_selecting && _selected.contains(s.id))
                          ? AppColors.secondaryColor
                          : Colors.blue,
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }

  /// Action card for a stop tapped on the map: order + name, then
  /// view detail / edit place / delete / dismiss.
  Widget _buildStopCard(RouteStop s) {
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
              CircleAvatar(
                radius: 12,
                backgroundColor: AppColors.primaryColor,
                child: Text(
                  '${s.stopOrder}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.stopName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'មើល (View detail)',
                icon: const Icon(
                  Icons.visibility,
                  color: AppColors.primaryColor,
                ),
                onPressed: () => _viewStopPlace(s),
              ),
              // Edit the incoming segment (previous stop → this stop). The
              // first stop has no incoming segment, so no button there.
              if (_stops.indexWhere((x) => x.id == s.id) > 0)
                IconButton(
                  tooltip: 'កែផ្លូវចូល (Edit segment)',
                  icon: const Icon(Icons.route, color: AppColors.primaryColor),
                  onPressed: () {
                    final i = _stops.indexWhere((x) => x.id == s.id);
                    if (i > 0) _fixSegment(i);
                  },
                ),
              IconButton(
                tooltip: 'លុប (Delete)',
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteStop(s),
              ),
              IconButton(
                tooltip: 'បិទ',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _mapSelected = null),
              ),
            ],
          ),
        ),
      ),
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
        final selected = _selected.contains(stop.id);
        return ListTile(
          selected: _selecting && selected,
          onTap: (_selecting && !_bulkDeleting)
              ? () => _toggleSelected(stop)
              : null,
          onLongPress: (!_selecting && !_bulkDeleting)
              ? () => setState(() {
                  _selecting = true;
                  _selected.add(stop.id);
                })
              : null,
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
            '${stop.location.latitude}, ${stop.location.longitude}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: _selecting
              ? Checkbox(
                  value: selected,
                  onChanged: _bulkDeleting
                      ? null
                      : (_) => _toggleSelected(stop),
                )
              : PopupMenuButton<String>(
            tooltip: 'ជម្រើស',
            onSelected: (v) {
              switch (v) {
                case 'fix':
                  _fixSegment(i);
                case 'place':
                  _changePlace(stop);
                case 'delete':
                  _deleteStop(stop);
              }
            },
            itemBuilder: (_) => [
              // First stop has no incoming segment to fix.
              if (i > 0)
                const PopupMenuItem(
                  value: 'fix',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.route),
                    title: Text('កែផ្លូវចូល (Fix road)'),
                  ),
                ),
              const PopupMenuItem(
                value: 'place',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.swap_horiz),
                  title: Text('ប្ដូរទីកន្លែង (Change place)'),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text(
                    'លុប (Delete)',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

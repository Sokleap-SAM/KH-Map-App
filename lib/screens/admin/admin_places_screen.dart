import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../models/place_category.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import '../../utils/constants/text_strings.dart';
import 'admin_map_size_button.dart';
import 'admin_place_detail_screen.dart';
import 'admin_place_edit_screen.dart';
import 'admin_place_request_history_screen.dart';
import 'admin_place_requests_screen.dart';

/// Places tab — CRUD over /places (all categories). Overview map shows every
/// place; filter by category chips + search by name; the list carries coords
/// and a lazily-loaded "used in N routes" count. Delete surfaces referencing
/// routes when the place is in use.
class AdminPlacesScreen extends StatefulWidget {
  const AdminPlacesScreen({super.key});

  @override
  State<AdminPlacesScreen> createState() => _AdminPlacesScreenState();
}

class _AdminPlacesScreenState extends State<AdminPlacesScreen> {
  final AdminService _service = AdminService();
  final MapController _mapController = MapController();

  /// Localized strings for the active language. `build` watches
  /// SettingsProvider, so reading here (listen:false) still rebuilds on change.
  AppTexts get _t => context.read<SettingsProvider>().t;

  List<Place> _places = const [];
  List<PlaceCategory> _categories = const [];
  int _pendingCount = 0;
  bool _loading = true;
  String? _error;
  String _filter = '';
  String? _categoryFilter; // category id, null = all
  Place? _selected;
  double _zoom = 12;

  // Resizable map "banner": fraction of body height.
  static const List<double> _mapSizes = [0.8, 0.6, 0.3, 0.1];
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
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    _loadPendingCount(); // fire-and-forget: badge only, must not block the list
    try {
      final results = await Future.wait([
        _service.fetchAllPlaces(),
        _service.fetchCategories(),
      ]);
      if (!mounted) return;
      setState(() {
        _places = results[0] as List<Place>;
        _categories = results[1] as List<PlaceCategory>;
        _usageCache.clear();
        // Re-resolve the selection against the fresh list; drops it if the
        // place was deleted.
        Place? sel;
        for (final p in _places) {
          if (p.id == _selected?.id) {
            sel = p;
            break;
          }
        }
        _selected = sel;
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

  Future<StopUsage> _usage(String placeId) =>
      _usageCache[placeId] ??= _service.fetchStopRoutes(placeId);

  /// Best-effort badge count of user requests awaiting review; a failure just
  /// leaves the badge hidden rather than erroring the whole screen.
  Future<void> _loadPendingCount() async {
    try {
      final pending = await _service.fetchPendingPlaceRequests();
      if (mounted) setState(() => _pendingCount = pending.length);
    } catch (_) {/* keep last known count */}
  }

  /// Opens the review queue; reloads on return since approving a request
  /// publishes a new place into this list.
  Future<void> _openRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminPlaceRequestsScreen()),
    );
    if (mounted) _load();
  }

  List<Place> get _filtered {
    final q = _filter.toLowerCase();
    return _places.where((p) {
      if (_categoryFilter != null && p.category?.id != _categoryFilter) {
        return false;
      }
      return q.isEmpty ||
          p.nameInKhmer.toLowerCase().contains(q) ||
          p.nameInLatin.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AdminPlaceEditScreen()),
    );
    if (ok == true) _load();
  }

  Future<void> _edit(Place p) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminPlaceEditScreen(existing: p)),
    );
    if (ok == true) _load();
  }

  Future<void> _openDetail(Place p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminPlaceDetailScreen(place: p)),
    );
    if (changed == true) _load();
  }

  void _select(Place p) {
    setState(() => _selected = p);
    _mapController.move(
      LatLng(p.latitude, p.longitude),
      _zoom < 16 ? 16 : _zoom,
    );
  }

  Future<void> _delete(Place p) async {
    final settings = context.read<SettingsProvider>();
    final t = settings.t;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.deletePlaceTitle),
        content: Text(t.deleteQuoted(p.localizedName(settings.languageCode))),
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
      await _service.deletePlace(p.id);
      _usageCache.remove(p.id);
      _load();
    } on AdminApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409 || e.statusCode == 400) {
        await _showInUse(p);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.failedWith(e.message))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.failedWith('$e'))));
    }
  }

  /// Place is referenced by routes — show which ones.
  Future<void> _showInUse(Place p) async {
    StopUsage? usage;
    try {
      usage = await _service.fetchStopRoutes(p.id);
    } catch (_) {}
    if (!mounted) return;
    final settings = context.read<SettingsProvider>();
    final t = settings.t;
    final routes = usage?.routes ?? const [];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.cannotDeleteInUse),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.usedInRoutes(
                p.localizedName(settings.languageCode),
                usage?.count ?? routes.length,
              ),
            ),
            const SizedBox(height: 8),
            if (routes.isEmpty)
              const Text('—')
            else
              ...routes.map(
                (r) => Text(
                  '• ${[if (r.code != null && r.code!.isNotEmpty) r.code, r.name ?? r.id].join('  ')}',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(t.yes),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Establishes the rebuild-on-language-change dependency; item builders read
    // the language with `read`.
    final t = context.watch<SettingsProvider>().t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.managePlaces),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _pendingCount > 0,
              label: Text('$_pendingCount'),
              child: const Icon(Icons.inbox_outlined),
            ),
            tooltip: t.placeRequestsTitle,
            onPressed: _openRequests,
          ),
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
        heroTag: 'admin_places_fab',
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.add_location_alt),
        label: Text(t.newPlace),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(AppTexts t) {
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
                  if (_selected != null) _buildSelectedCard(_selected!),
                ],
              ),
            ),
            _buildCategoryFilter(t),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: t.searchByName,
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

  Widget _buildCategoryFilter(AppTexts t) {
    if (_categories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t.all),
              selected: _categoryFilter == null,
              onSelected: (_) => setState(() => _categoryFilter = null),
            ),
          ),
          for (final c in _categories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c.name),
                selected: _categoryFilter == c.id,
                onSelected: (_) => setState(() => _categoryFilter = c.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewMap() {
    final visible = _filtered;
    final center = _selected != null
        ? LatLng(_selected!.latitude, _selected!.longitude)
        : (visible.isNotEmpty
              ? LatLng(visible.first.latitude, visible.first.longitude)
              : const LatLng(11.5564, 104.9282));
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
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
            for (final p in visible)
              () {
                final loc = LatLng(p.latitude, p.longitude);
                final selected = _selected?.id == p.id;
                final showIcon = selected || _zoom >= 15.0;
                final size = selected
                    ? 30.0
                    : showIcon
                    ? 24.0
                    : 8.0;
                return Marker(
                  point: loc,
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _select(p),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected ? Colors.red : AppColors.primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: showIcon ? 2 : 1,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 3),
                        ],
                      ),
                      child: showIcon
                          ? Icon(
                              Icons.place,
                              color: Colors.white,
                              size: size * 0.6,
                            )
                          : null,
                    ),
                  ),
                );
              }(),
          ],
        ),
      ],
    );
  }

  /// Action card shown over the map when a place marker is tapped:
  /// view (detail screen) / edit / delete / dismiss.
  Widget _buildSelectedCard(Place p) {
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
              const Icon(Icons.place, color: AppColors.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.localizedName(
                        context.read<SettingsProvider>().languageCode,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      p.category?.name ?? '—',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _t.view,
                icon: const Icon(
                  Icons.visibility,
                  color: AppColors.primaryColor,
                ),
                onPressed: () => _openDetail(p),
              ),
              IconButton(
                tooltip: _t.edit,
                icon: const Icon(Icons.edit, color: AppColors.secondaryColor),
                onPressed: () => _edit(p),
              ),
              IconButton(
                tooltip: _t.delete,
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _delete(p),
              ),
              IconButton(
                tooltip: _t.close,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _selected = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(AppTexts t) {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(child: Text(t.noPlaces));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = items[i];
          return ListTile(
            leading: const Icon(Icons.place, color: AppColors.primaryColor),
            title: Text(
              p.localizedName(context.read<SettingsProvider>().languageCode),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.category?.name ?? '—'} · '
                  '${p.latitude}, ${p.longitude}',
                  style: const TextStyle(fontSize: 11),
                ),
                _UsageLabel(future: _usage(p.id)),
              ],
            ),
            isThreeLine: true,
            onTap: () {
              _select(p);
              _openDetail(p);
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
        final t = context.watch<SettingsProvider>().t;
        String text;
        if (snap.connectionState != ConnectionState.done) {
          text = t.usageNA;
        } else if (snap.hasError) {
          text = t.usageUnavailable;
        } else {
          text = t.usedInNRoutes(snap.data!.count);
        }
        return Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        );
      },
    );
  }
}

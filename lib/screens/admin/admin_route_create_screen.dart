import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/route_stop.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';
import 'admin_map_size_button.dart';

/// Multi-step route builder that composes a route from EXISTING places.
///
/// Step 1 — metadata (name / code / isLine).            [create only]
/// Step 2 — pick an ordered sequence of stops from existing places. The same
///          place may be picked again (loops); reorder via drag-and-drop.
/// Step 3 — connect each consecutive pair with a manually-drawn polyline
///          (tap vertices; "Suggest" seeds a draft; "Clear"/"Done").
/// Step 4 — review + submit ONE POST /transit/admin/route-stops/bulk with each
///          stop as `{ placeId, segmentFromPrevious? }`.
///
/// Nothing hits the backend until the Step 4 submit. Returns the affected
/// route id on success, or null if cancelled.
///
/// Append mode ([appendRouteId] set): no metadata step; the first segment
/// connects the existing last stop → the first newly-picked stop; submit
/// includes `routeId` and omits name/code/isLine.
class AdminRouteCreateScreen extends StatefulWidget {
  final String? appendRouteId;
  final String? appendRouteLabel;
  final List<RouteStop> existingStops;

  const AdminRouteCreateScreen({
    super.key,
    this.appendRouteId,
    this.appendRouteLabel,
    this.existingStops = const [],
  });

  bool get isAppend => appendRouteId != null;

  @override
  State<AdminRouteCreateScreen> createState() => _AdminRouteCreateScreenState();
}

/// A picked stop in the sequence. [key] is unique per position so the same
/// place can appear multiple times and still reorder correctly.
class _SeqItem {
  final int key;
  final Place place;
  const _SeqItem(this.key, this.place);
}

/// One segment to draw: from [prev] to [curr]. [toIndex] is the sequence index
/// the segment arrives at (used to attach segmentFromPrevious on submit).
class _SegSpec {
  final LatLng prev;
  final String prevName;
  final LatLng curr;
  final String currName;
  final int toIndex;
  const _SegSpec({
    required this.prev,
    required this.prevName,
    required this.curr,
    required this.currName,
    required this.toIndex,
  });
}

class _AdminRouteCreateScreenState extends State<AdminRouteCreateScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  bool _isLine = true;

  int _step = 1;

  // Places catalogue.
  List<Place> _places = const [];
  bool _loadingPlaces = true;
  String? _placesError;

  // Step 2 — chosen sequence.
  final List<_SeqItem> _sequence = [];
  int _seqKeyCounter = 0;
  String _filter = '';

  // Resizable picker map (60% → 30% → 10% of body height).
  static const List<double> _mapSizes = [0.6, 0.3, 0.1];
  double _mapFraction = 0.3;
  void _cycleMapSize() {
    final i = _mapSizes.indexOf(_mapFraction);
    setState(() => _mapFraction = _mapSizes[(i + 1) % _mapSizes.length]);
  }

  // Step 3 — connect.
  List<_SegSpec> _specs = const [];
  final List<List<LatLng>> _segments = [];
  int _connectingIndex = 0;
  List<LatLng> _working = [];
  bool _suggesting = false;
  bool _penMode = false; // when true, map taps add vertices

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAppend) _step = 2; // no metadata step when appending
    _loadPlaces();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      final places = await AdminService().fetchPlaces();
      if (!mounted) return;
      setState(() {
        _places = places;
        _loadingPlaces = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _placesError = e is AdminApiException ? e.message : e.toString();
        _loadingPlaces = false;
      });
    }
  }

  LatLng _ll(Place p) => LatLng(p.latitude, p.longitude);
  int get _orderOffset => widget.existingStops.length;

  // ─────────────────────────── Step 1: metadata ──────────────────────────────

  void _doneMetadata() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('សូមបញ្ចូលឈ្មោះផ្លូវ (Route name required)'),
        ),
      );
      return;
    }
    setState(() => _step = 2);
  }

  // ─────────────────────────── Step 2: sequence ──────────────────────────────

  List<Place> get _filteredPlaces {
    if (_filter.isEmpty) return _places;
    final q = _filter.toLowerCase();
    return _places.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  void _addToSequence(Place p) {
    setState(() => _sequence.add(_SeqItem(_seqKeyCounter++, p)));
  }

  void _removeFromSequence(int index) {
    setState(() => _sequence.removeAt(index));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _sequence.removeAt(oldIndex);
      _sequence.insert(newIndex, item);
    });
  }

  void _doneSequence() {
    if (_sequence.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('សូមជ្រើសរើសចំណតយ៉ាងតិច១ (Pick at least one stop)'),
        ),
      );
      return;
    }
    final specs = <_SegSpec>[];
    if (widget.isAppend && widget.existingStops.isNotEmpty) {
      final last = widget.existingStops.last;
      specs.add(
        _SegSpec(
          prev: last.location,
          prevName: last.stopName,
          curr: _ll(_sequence[0].place),
          currName: _sequence[0].place.name,
          toIndex: 0,
        ),
      );
    }
    for (int i = 1; i < _sequence.length; i++) {
      specs.add(
        _SegSpec(
          prev: _ll(_sequence[i - 1].place),
          prevName: _sequence[i - 1].place.name,
          curr: _ll(_sequence[i].place),
          currName: _sequence[i].place.name,
          toIndex: i,
        ),
      );
    }

    setState(() {
      _specs = specs;
      _segments.clear();
      if (specs.isEmpty) {
        _step = 4; // single-stop new route — nothing to connect
      } else {
        _step = 3;
        _connectingIndex = 0;
        _working = [specs.first.prev];
        _penMode = false;
      }
    });
  }

  // ─────────────────────────── Step 3: connect ───────────────────────────────

  void _onTapConnect(LatLng point) {
    if (!_penMode) return; // only draw when the pen is active
    setState(() => _working = [..._working, point]);
  }

  /// Discard the suggested/drawn line back to just the start anchor so the
  /// admin can redraw from scratch.
  void _removeSuggestion() {
    final spec = _specs[_connectingIndex];
    setState(() => _working = [spec.prev]);
  }

  Future<void> _suggestSegment() async {
    final spec = _specs[_connectingIndex];
    setState(() => _suggesting = true);
    try {
      final path = await AdminService().suggestPath(
        from: spec.prev,
        to: spec.curr,
      );
      if (!mounted) return;
      setState(
        () => _working = path.isNotEmpty ? path : [spec.prev, spec.curr],
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Suggest path failed: $msg')));
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  void _doneSegment() {
    final spec = _specs[_connectingIndex];
    final pts = List<LatLng>.from(_working);
    if (pts.isEmpty) {
      pts.add(spec.prev);
    } else {
      pts[0] = spec.prev;
    }
    if (pts.last != spec.curr) pts.add(spec.curr);
    if (pts.length < 2) {
      pts
        ..clear()
        ..addAll([spec.prev, spec.curr]);
    }
    setState(() {
      _segments.add(pts);
      if (_connectingIndex + 1 < _specs.length) {
        _connectingIndex++;
        _working = [_specs[_connectingIndex].prev];
        _penMode = false;
      } else {
        _step = 4;
      }
    });
  }

  // ─────────────────────────── Step 4: submit ────────────────────────────────

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final payload = <BulkStopRef>[];
      for (int i = 0; i < _sequence.length; i++) {
        List<List<double>>? seg;
        final specIdx = _specs.indexWhere((s) => s.toIndex == i);
        if (specIdx != -1 && specIdx < _segments.length) {
          seg = _segments[specIdx]
              .map((p) => [p.longitude, p.latitude])
              .toList();
        }
        payload.add(
          BulkStopRef(placeId: _sequence[i].place.id, segmentFromPrevious: seg),
        );
      }

      final routeId = await AdminService().bulkCreateRouteStops(
        stops: payload,
        routeId: widget.appendRouteId,
        name: widget.isAppend ? null : _nameCtrl.text.trim(),
        code: widget.isAppend
            ? null
            : (_codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim()),
        isLine: widget.isAppend ? null : _isLine,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAppend
                ? 'បានបន្ថែមចំណត (Stops appended)'
                : 'បានបង្កើតផ្លូវ (Route created)',
          ),
        ),
      );
      Navigator.of(context).pop(routeId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('បរាជ័យ: $msg')));
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('បោះបង់?'),
        content: const Text(
          'ការងារនឹងបាត់បង់ (Your work will be lost). Cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('ទេ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('បាទ/ចាស', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  // ──────────────────────────── Map geometry ─────────────────────────────────

  List<LatLng> _existingPolyline() {
    final out = <LatLng>[];
    for (final s in widget.existingStops) {
      if (s.segmentPath != null && s.segmentPath!.isNotEmpty) {
        out.addAll(s.segmentPath!);
      } else {
        out.add(s.location);
      }
    }
    return out;
  }

  LatLng get _initialCenter {
    if (widget.existingStops.isNotEmpty) {
      return widget.existingStops.last.location;
    }
    if (_places.isNotEmpty) return _ll(_places.first);
    return const LatLng(11.5564, 104.9282);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          title: Text(
            widget.isAppend
                ? 'បន្ថែមចំណត · ${widget.appendRouteLabel ?? ''}'
                : 'បង្កើតផ្លូវថ្មី',
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              child: const Text(
                'បោះបង់',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 1:
        return _buildMetadataStep();
      case 2:
        return _buildSequenceStep();
      case 3:
        return _buildConnectStep();
      default:
        return _buildReviewStep();
    }
  }

  // Step 1 UI
  Widget _buildMetadataStep() {
    return Column(
      children: [
        const _StepBanner(text: 'ដំណាក់កាល ១/៤ · ព័ត៌មានផ្លូវ (Route info)'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ឈ្មោះផ្លូវ (Name)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                decoration: const InputDecoration(
                  labelText: 'កូដ (Code, optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(
                  _isLine
                      ? 'ប្រភេទ: បន្ទាត់ (Line — A→B)'
                      : 'ប្រភេទ: រង្វង់ (Circular loop)',
                ),
                value: _isLine,
                onChanged: (v) => setState(() => _isLine = v),
              ),
            ],
          ),
        ),
        _bottomButton('បន្ត (Next: pick stops)', _doneMetadata),
      ],
    );
  }

  // Step 2 UI
  Widget _buildSequenceStep() {
    if (_loadingPlaces) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_placesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_placesError!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return Column(
      children: [
        _StepBanner(
          text: 'ដំណាក់កាល ២/៤ · ជ្រើសរើសលំដាប់ចំណត (${_sequence.length})',
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mapHeight = constraints.maxHeight * _mapFraction;
              return Column(
                children: [
                  SizedBox(
                    height: mapHeight,
                    child: Stack(
                      children: [
                        _buildPickerMap(),
                        MapSizeButton(
                          fraction: _mapFraction,
                          onTap: _cycleMapSize,
                        ),
                      ],
                    ),
                  ),
                  _buildSequenceStrip(),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: _filterCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'ស្វែងរកចំណត (Filter places)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  Expanded(child: _buildPlacePicker()),
                ],
              );
            },
          ),
        ),
        _bottomButton('បន្ត (Next: connect)', _doneSequence),
      ],
    );
  }

  Widget _buildPickerMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _initialCenter, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        if (_existingPolyline().length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _existingPolyline(),
                color: Colors.grey,
                strokeWidth: 4,
              ),
            ],
          ),
        MarkerLayer(markers: _pickerMarkers()),
      ],
    );
  }

  List<Marker> _pickerMarkers() {
    final markers = <Marker>[];
    final existingIds = widget.existingStops.map((s) => s.stopId).toSet();

    // Existing route stops (append): start/end accented, middle grey dots, so
    // the admin sees what's already on the route and where it ends.
    final lastIdx = widget.existingStops.length - 1;
    for (int i = 0; i < widget.existingStops.length; i++) {
      final s = widget.existingStops[i];
      if (i == 0 || i == lastIdx) {
        markers.add(_pin(s.location, i == 0 ? Colors.green : Colors.red,
            i == 0 ? Icons.play_arrow : Icons.flag));
      } else {
        markers.add(_smallDot(s.location, Colors.grey));
      }
    }

    // Available (unselected) places — dark tappable add-pins. Picked stops are
    // drawn below as gold numbered pins, and existing-route stops above, so a
    // selected stop reads purely as gold (re-add from the list for a loop).
    final pickedIds = _sequence.map((it) => it.place.id).toSet();
    for (final p in _places) {
      if (existingIds.contains(p.id) || pickedIds.contains(p.id)) continue;
      markers.add(
        Marker(
          point: _ll(p),
          width: 24,
          height: 24,
          child: GestureDetector(
            onTap: () => _addToSequence(p),
            child: const Icon(Icons.add_location,
                size: 22, color: AppColors.primaryColor),
          ),
        ),
      );
    }

    // Stops already picked into the sequence — numbered gold pins on top.
    for (int i = 0; i < _sequence.length; i++) {
      markers.add(_numberPin(_ll(_sequence[i].place), _orderOffset + i + 1));
    }
    return markers;
  }

  Marker _smallDot(LatLng p, Color color) => Marker(
        point: p,
        width: 18,
        height: 18,
        child: Icon(Icons.circle, size: 11, color: color),
      );

  Marker _numberPin(LatLng p, int n) => Marker(
        point: p,
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.secondaryColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Text('$n',
              style: const TextStyle(
                  color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _buildSequenceStrip() {
    if (_sequence.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('មិនទាន់ជ្រើសរើស (No stops picked — tap a place to add)'),
      );
    }
    return SizedBox(
      height: 132,
      child: ReorderableListView.builder(
        buildDefaultDragHandles: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _sequence.length,
        onReorder: _reorder,
        itemBuilder: (_, i) {
          final item = _sequence[i];
          return ListTile(
            key: ValueKey(item.key),
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: const Color.fromARGB(255, 82, 172, 255),
              child: Text(
                '${_orderOffset + i + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            title: Text(item.place.name),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18, color: Colors.red),
              onPressed: () => _removeFromSequence(i),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlacePicker() {
    final items = _filteredPlaces;
    if (items.isEmpty) {
      return const Center(child: Text('មិនមានចំណត'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = items[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.place, color: AppColors.primaryColor),
          title: Text(p.name),
          subtitle: Text(
            '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 11),
          ),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: () => _addToSequence(p),
        );
      },
    );
  }

  // Step 3 UI
  Widget _buildConnectStep() {
    final spec = _specs[_connectingIndex];
    return Column(
      children: [
        _StepBanner(
          text:
              'ដំណាក់កាល ៣/៤ · Segment ${_connectingIndex + 1} / ${_specs.length}\n'
              '${spec.prevName} → ${spec.currName}',
        ),
        Expanded(
          child: Stack(
            children: [
              _buildConnectMap(),
              _MapHint(
                _penMode
                    ? '✏️ គូរពី ▶ ទៅ 🚩 (Draw ▶ → 🚩) · ${_working.length} vertices'
                    : 'អូស/ពង្រីកបាន · ចុច "Pen" ដើម្បីគូរ (Tap Pen to draw)',
              ),
            ],
          ),
        ),
        _buildConnectBar(),
      ],
    );
  }

  Widget _buildConnectMap() {
    final highlight = _specs[_connectingIndex];
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: highlight.prev,
        initialZoom: 14,
        onTap: (_, point) => _onTapConnect(point),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        if (_existingPolyline().length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _existingPolyline(),
                color: Colors.grey,
                strokeWidth: 4,
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            for (final seg in _segments)
              Polyline(points: seg, color: Colors.blueAccent, strokeWidth: 5),
          ],
        ),
        if (_working.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _working,
                color: AppColors.secondaryColor,
                strokeWidth: 4,
              ),
            ],
          ),
        // Live "closing" guide: from the last drawn vertex to the END stop so
        // the admin always sees the segment finishing at the correct stop.
        // (On Done the endpoints are snapped to prev/curr exactly.)
        if (_working.isNotEmpty && _working.last != highlight.curr)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_working.last, highlight.curr],
                color: Colors.red.withValues(alpha: 0.4),
                strokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(markers: _connectMarkers(highlight)),
      ],
    );
  }

  List<Marker> _connectMarkers(_SegSpec highlight) {
    final markers = <Marker>[];
    // Two active endpoints.
    markers.add(_pin(highlight.prev, Colors.green, Icons.play_arrow));
    markers.add(_pin(highlight.curr, Colors.red, Icons.flag));
    // Other sequence stops dimmed.
    for (int i = 0; i < _sequence.length; i++) {
      final p = _ll(_sequence[i].place);
      if (p == highlight.prev || p == highlight.curr) continue;
      markers.add(
        Marker(
          point: p,
          width: 18,
          height: 18,
          child: Icon(
            Icons.circle,
            size: 11,
            color: AppColors.secondaryColor.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return markers;
  }

  Marker _pin(LatLng p, Color color, IconData icon) {
    return Marker(
      point: p,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildConnectBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _suggesting
                        ? null
                        : () => setState(() => _penMode = !_penMode),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: _penMode
                          ? AppColors.secondaryColor.withValues(alpha: 0.18)
                          : null,
                    ),
                    icon: Icon(_penMode ? Icons.edit : Icons.edit_outlined),
                    label: Text(_penMode ? 'Drawing' : 'Pen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _suggesting ? null : _suggestSegment,
                    icon: _suggesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: const Text('Suggest'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _suggesting ? null : _removeSuggestion,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _suggesting ? null : _doneSegment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.check),
                label: const Text('Done segment'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Step 4 UI
  Widget _buildReviewStep() {
    return Column(
      children: [
        const _StepBanner(text: 'ដំណាក់កាល ៤/៤ · ពិនិត្យ & រក្សាទុក (Review)'),
        Expanded(child: _buildReviewMap()),
        _buildReviewSummary(),
        _bottomButton(
          widget.isAppend
              ? 'រក្សាទុកចំណត (${_sequence.length})'
              : 'បង្កើតផ្លូវ (${_sequence.length} stops)',
          _submitting ? null : _submit,
          busy: _submitting,
        ),
      ],
    );
  }

  Widget _buildReviewMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _initialCenter, initialZoom: 13),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        if (_existingPolyline().length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _existingPolyline(),
                color: Colors.grey,
                strokeWidth: 4,
              ),
            ],
          ),
        PolylineLayer(
          polylines: [
            for (final seg in _segments)
              Polyline(points: seg, color: Colors.blueAccent, strokeWidth: 5),
          ],
        ),
        MarkerLayer(
          markers: [
            for (int i = 0; i < _sequence.length; i++)
              Marker(
                point: _ll(_sequence[i].place),
                width: 26,
                height: 26,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.secondaryColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${_orderOffset + i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildReviewSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.black12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isAppend)
            Text(
              '${_codeCtrl.text.trim().isEmpty ? '' : '${_codeCtrl.text.trim()}  '}'
              '${_nameCtrl.text.trim()}  ·  ${_isLine ? 'Line' : 'Circular'}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          Text('${_sequence.length} stops · ${_segments.length} segments'),
        ],
      ),
    );
  }

  // ──────────────────────────── small helpers ────────────────────────────────

  Widget _bottomButton(
    String label,
    VoidCallback? onPressed, {
    bool busy = false,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _StepBanner extends StatelessWidget {
  final String text;
  const _StepBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.primaryColor.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class _MapHint extends StatelessWidget {
  final String text;
  const _MapHint(this.text);
  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Material(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

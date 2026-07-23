import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/place.dart';
import '../../models/route_stop.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/text_strings.dart';
import '../../utils/constants/colors.dart';
import 'admin_color_picker.dart';
import 'admin_map_size_button.dart';

/// Multi-step route builder that composes a route from EXISTING places.
///
/// Step 1 — metadata (name / code / isLine).            [create only]
/// Step 2 — pick an ordered sequence of stops from existing places. The same
///          place may be picked again (loops); reorder via drag-and-drop.
/// Step 3 — per consecutive pair: a Valhalla suggestion (suggest-path) is
///          previewed first. If the suggested road is wrong, the admin taps
///          the map to hand-draw the line: taps become exact vertices joined
///          by straight lines, anchored to the suggestion's first/last road
///          coordinates. What is drawn is exactly what gets stored — the
///          drawer must trace the road carefully.
/// Step 4 — review + submit ONE POST /transit/admin/route-stops/bulk. Untouched
///          segments send only `{ placeId }` (backend computes the road);
///          hand-drawn ones add `segmentFromPrevious` stored verbatim.
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

/// A finished segment draft. [manual] == false → [path] is the Valhalla
/// suggestion and nothing is submitted (the backend recomputes the same
/// road). [manual] == true → the admin hand-drew the line; [path] is
/// submitted verbatim as `segmentFromPrevious` and stored exactly as drawn.
class _SegmentDraft {
  final List<LatLng> path;
  final bool manual;
  const _SegmentDraft({required this.path, required this.manual});
}

/// One segment to preview: from [prev] to [curr]. [toIndex] is the sequence
/// index the segment arrives at (used to attach vias on submit).
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
  AppTexts get _t => context.read<SettingsProvider>().t;

  final MapController _mapController = MapController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  // Backend `isLine`: true = directional line, false = circular loop. The UI
  // toggle below is "Loop (circular)", so state is kept as `_isLoop` and
  // converted to `isLine: !_isLoop` when sent.
  bool _isLoop = false; // true = circular loop, false = directional line
  String _direction = 'outbound'; // 'outbound' | 'inbound' (lines only)
  String _color = '#2196F3'; // route color (create mode)
  Color get _routeColor => routeColorFromHex(_color) ?? Colors.blueAccent;

  int _step = 1;

  // Places catalogue.
  List<Place> _places = const [];
  bool _loadingPlaces = true;
  String? _placesError;

  // Step 2 — chosen sequence.
  final List<_SeqItem> _sequence = [];
  int _seqKeyCounter = 0;
  String _filter = '';

  // Resizable picker map (50% → 30% → 10% of body height).
  static const List<double> _mapSizes = [0.5, 0.3, 0.1];
  double _mapFraction = 0.3;
  void _cycleMapSize() {
    final i = _mapSizes.indexOf(_mapFraction);
    setState(() => _mapFraction = _mapSizes[(i + 1) % _mapSizes.length]);
  }

  // Step 3 — Valhalla suggestion + optional manual draw. Map taps are exact
  // polyline vertices connected by straight lines, anchored to the
  // suggestion's road endpoints.
  List<_SegSpec> _specs = const [];
  final List<_SegmentDraft> _segments = [];
  int _connectingIndex = 0;
  List<LatLng> _points = [];
  List<LatLng> _preview = [];
  bool _suggesting = false;

  /// The hand-drawn line: Valhalla's first coord → tapped points → Valhalla's
  /// last coord. Falls back to the raw points when the suggestion is missing.
  List<LatLng> get _manualPath => [
    if (_preview.isNotEmpty) _preview.first,
    ..._points,
    if (_preview.length >= 2) _preview.last,
  ];

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
        SnackBar(content: Text(_t.routeNameRequired)),
      );
      return;
    }
    setState(() => _step = 2);
  }

  // ─────────────────────────── Step 2: sequence ──────────────────────────────

  List<Place> get _filteredPlaces {
    if (_filter.isEmpty) return _places;
    final q = _filter.toLowerCase();
    return _places
        .where((p) =>
            p.nameInKhmer.toLowerCase().contains(q) ||
            p.nameInLatin.toLowerCase().contains(q))
        .toList();
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
        SnackBar(content: Text(_t.pickAtLeastOneStop)),
      );
      return;
    }
    final lang = context.read<SettingsProvider>().languageCode;
    final specs = <_SegSpec>[];
    if (widget.isAppend && widget.existingStops.isNotEmpty) {
      final last = widget.existingStops.last;
      specs.add(
        _SegSpec(
          prev: last.location,
          prevName: last.localizedStopName(lang),
          curr: _ll(_sequence[0].place),
          currName: _sequence[0].place.localizedName(lang),
          toIndex: 0,
        ),
      );
    }
    for (int i = 1; i < _sequence.length; i++) {
      specs.add(
        _SegSpec(
          prev: _ll(_sequence[i - 1].place),
          prevName: _sequence[i - 1].place.localizedName(lang),
          curr: _ll(_sequence[i].place),
          currName: _sequence[i].place.localizedName(lang),
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
        _points = [];
        _preview = [];
      }
    });
    if (specs.isNotEmpty) _suggestSegment();
  }

  // ─────────────────────── Step 3: suggest + manual draw ─────────────────────

  /// Map tap = a vertex of the hand-drawn line. Vertices connect with
  /// straight lines, anchored to the suggestion's road endpoints — what is
  /// drawn is exactly what gets stored, so trace the road carefully.
  void _onTapConnect(LatLng point) {
    setState(() => _points = [..._points, point]);
  }

  /// Drop the last drawn vertex.
  void _undoPoint() {
    if (_points.isEmpty) return;
    setState(() => _points = _points.sublist(0, _points.length - 1));
  }

  /// Discard the drawing — back to the Valhalla suggestion alone.
  void _clearPoints() {
    setState(() => _points = []);
  }

  /// Fetch the Valhalla road suggestion between the two stops. Its first and
  /// last coordinates also anchor the hand-drawn line to the road.
  Future<void> _suggestSegment() async {
    final spec = _specs[_connectingIndex];
    setState(() => _suggesting = true);
    try {
      final path = await AdminService().suggestPath(
        from: spec.prev,
        to: spec.curr,
      );
      if (!mounted) return;
      setState(() => _preview = path);
    } catch (e) {
      if (!mounted) return;
      setState(() => _preview = []);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Suggest path failed: $msg')));
    } finally {
      if (mounted) setState(() => _suggesting = false);
    }
  }

  /// Accept the segment: hand-drawn line when vertices exist, otherwise the
  /// Valhalla suggestion. Stop coordinates are never stitched in — stops are
  /// markers only.
  void _doneSegment() {
    final manual = _points.isNotEmpty;
    setState(() {
      _segments.add(
        _SegmentDraft(
          path: manual ? _manualPath : List<LatLng>.from(_preview),
          manual: manual,
        ),
      );
      if (_connectingIndex + 1 < _specs.length) {
        _connectingIndex++;
        _points = [];
        _preview = [];
      } else {
        _step = 4;
      }
    });
    if (_step == 3) _suggestSegment();
  }

  // ─────────────────────────── Step 4: submit ────────────────────────────────

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // Untouched segments send only the placeId — the backend computes the
      // road geometry. Hand-drawn segments go verbatim as
      // `segmentFromPrevious` and are stored exactly as drawn.
      final payload = <BulkStopRef>[];
      for (int i = 0; i < _sequence.length; i++) {
        List<List<double>>? seg;
        final specIdx = _specs.indexWhere((s) => s.toIndex == i);
        if (specIdx != -1 && specIdx < _segments.length) {
          final draft = _segments[specIdx];
          if (draft.manual && draft.path.length >= 2) {
            seg = draft.path.map((p) => [p.longitude, p.latitude]).toList();
          }
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
        isLine: widget.isAppend ? null : !_isLoop,
        color: widget.isAppend ? null : _color,
        // Loops have no direction; only directional lines send one.
        direction: (widget.isAppend || _isLoop) ? null : _direction,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isAppend ? _t.stopsAppended : _t.routeCreated,
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
      ).showSnackBar(SnackBar(content: Text(_t.failedWith(msg))));
    }
  }

  Future<void> _cancel() async {
    final t = _t;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.cancelQuestion),
        content: Text(t.workWillBeLost),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.no),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.yes, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  // ──────────────────────────── Map geometry ─────────────────────────────────

  /// Existing route geometry: the stored segments only. Stop coordinates are
  /// markers, never part of the line (segments are stitched server-side).
  /// Legacy routes without any segment geometry fall back to stop-to-stop.
  List<LatLng> _existingPolyline() {
    final out = <LatLng>[];
    for (final s in widget.existingStops) {
      if (s.segmentPath != null && s.segmentPath!.isNotEmpty) {
        out.addAll(s.segmentPath!);
      }
    }
    if (out.isEmpty && widget.existingStops.length >= 2) {
      return [for (final s in widget.existingStops) s.location];
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
    // Rebuild-on-language-change dependency; helpers below use `read`.
    context.watch<SettingsProvider>();
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
                ? _t.appendStopsLabel(widget.appendRouteLabel ?? '')
                : _t.newRouteTitle,
          ),
          actions: [
            TextButton(
              onPressed: _cancel,
              child: Text(
                _t.cancel,
                style: const TextStyle(color: Colors.white),
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
    final t = _t;
    return Column(
      children: [
        _StepBanner(text: t.stepRouteInfo),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: t.routeNameField,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                decoration: InputDecoration(
                  labelText: t.codeOptional,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.loopCircular),
                subtitle: Text(
                  _isLoop ? t.departureEqualsTerminal : t.directionalLine,
                ),
                value: _isLoop,
                onChanged: (v) => setState(() => _isLoop = v),
              ),
              if (!_isLoop)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.direction,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _directionOption(
                              value: 'outbound',
                              icon: Icons.arrow_forward,
                              label: t.outbound,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _directionOption(
                              value: 'inbound',
                              icon: Icons.arrow_back,
                              label: t.inbound,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          t.directionPairingNote,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.routeColor),
                subtitle: Text(_color),
                trailing: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: routeColorFromHex(_color) ?? Colors.blue,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                  ),
                ),
                onTap: () async {
                  final picked = await showRouteColorPicker(
                    context,
                    initialHex: _color,
                  );
                  if (picked != null) setState(() => _color = picked);
                },
              ),
            ],
          ),
        ),
        _bottomButton(t.nextPickStops, _doneMetadata),
      ],
    );
  }

  Widget _directionOption({
    required String value,
    required IconData icon,
    required String label,
  }) {
    final selected = _direction == value;
    final fg = selected ? Colors.white : AppColors.primaryColor;
    return Material(
      color: selected ? AppColors.secondaryColor : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _direction = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.secondaryColor : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(color: fg, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
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
        _StepBanner(text: _t.stepPickStops(_sequence.length)),
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
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _t.filterPlaces,
                        border: const OutlineInputBorder(),
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
        _bottomButton(_t.nextConnect, _doneSequence),
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

  Place? _placeById(String id) {
    for (final p in _places) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<Marker> _pickerMarkers() {
    final markers = <Marker>[];
    final existingIds = widget.existingStops.map((s) => s.stopId).toSet();

    // Existing route stops (append): start/end accented, middle grey dots, so
    // the admin sees what's already on the route and where it ends. Tappable
    // too — e.g. append the route's first stop again to close a loop. When
    // the place isn't in the picker catalogue (other stop category), build it
    // from the route-stop itself so the tap still works.
    final lastIdx = widget.existingStops.length - 1;
    for (int i = 0; i < widget.existingStops.length; i++) {
      final s = widget.existingStops[i];
      final place =
          _placeById(s.stopId) ??
          Place(
            id: s.stopId,
            nameInKhmer: s.stopName,
            nameInLatin: s.stopNameLatin ?? s.stopName,
            longitude: s.location.longitude,
            latitude: s.location.latitude,
            photos: const [],
          );
      void onTap() => _addToSequence(place);
      if (i == 0 || i == lastIdx) {
        markers.add(
          _pin(
            s.location,
            i == 0 ? Colors.green : Colors.red,
            i == 0 ? Icons.play_arrow : Icons.flag,
            onTap: onTap,
          ),
        );
      } else {
        markers.add(_smallDot(s.location, Colors.grey, onTap: onTap));
      }
    }

    // Available (unselected) places — dark tappable add-pins. Picked stops are
    // drawn below as gold numbered pins, and existing-route stops above, so a
    // selected stop reads purely as gold.
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
            child: const Icon(
              Icons.add_location,
              size: 22,
              color: AppColors.primaryColor,
            ),
          ),
        ),
      );
    }

    // Stops already picked into the sequence — numbered gold pins on top.
    // Tapping a gold pin re-adds that place, so a circular route can pick the
    // same stop as first and last straight from the map.
    for (int i = 0; i < _sequence.length; i++) {
      final place = _sequence[i].place;
      markers.add(
        _numberPin(
          _ll(place),
          _orderOffset + i + 1,
          onTap: () => _addToSequence(place),
        ),
      );
    }
    return markers;
  }

  Marker _smallDot(LatLng p, Color color, {VoidCallback? onTap}) => Marker(
    point: p,
    width: 18,
    height: 18,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(Icons.circle, size: 11, color: color),
    ),
  );

  Marker _numberPin(LatLng p, int n, {VoidCallback? onTap}) => Marker(
    point: p,
    width: 28,
    height: 28,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.secondaryColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ),
  );

  Widget _buildSequenceStrip() {
    if (_sequence.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_t.noStopsPicked),
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
            title: Text(
              item.place.localizedName(
                context.read<SettingsProvider>().languageCode,
              ),
            ),
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
      return Center(child: Text(_t.noStops));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = items[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.place, color: AppColors.primaryColor),
          title: Text(
            p.localizedName(context.read<SettingsProvider>().languageCode),
          ),
          subtitle: Text(
            '${p.latitude}, ${p.longitude}',
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
    final t = _t;
    return Column(
      children: [
        _StepBanner(
          text: t.segmentStepBanner(
            _connectingIndex + 1,
            _specs.length,
            spec.prevName,
            spec.currName,
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              _buildConnectMap(),
              _MapHint(
                _suggesting
                    ? t.fetchingSuggestion
                    : _points.isNotEmpty
                    ? t.manualDrawHint(_points.length)
                    : _preview.isEmpty
                    ? t.noSuggestionDrawHint
                    : t.wrongRoadDrawHint,
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
              if (seg.path.length >= 2)
                Polyline(points: seg.path, color: _routeColor, strokeWidth: 5),
          ],
        ),
        // Valhalla suggestion: the active line when nothing is drawn, a faint
        // reference underlay once the admin starts drawing over it.
        if (_preview.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _preview,
                color: _points.isEmpty
                    ? AppColors.secondaryColor
                    : AppColors.secondaryColor.withValues(alpha: 0.3),
                strokeWidth: 4,
              ),
            ],
          ),
        // Hand-drawn line: suggestion's road endpoints + tapped vertices,
        // connected with straight lines — stored exactly as drawn.
        if (_points.isNotEmpty && _manualPath.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _manualPath,
                color: AppColors.secondaryColor,
                strokeWidth: 4,
              ),
            ],
          ),
        // The line starts/ends on the ROAD beside each stop, never at the
        // stop marker — link them with short dashed connectors.
        if ((_points.isEmpty ? _preview : _manualPath).length >= 2)
          PolylineLayer(
            polylines: _stopConnectors(
              _points.isEmpty ? _preview : _manualPath,
              highlight.prev,
              highlight.curr,
            ),
          ),
        MarkerLayer(markers: _connectMarkers(highlight)),
      ],
    );
  }

  /// Short dashed lines linking each stop marker (sidewalk) to the nearest
  /// end of the road-snapped path — purely visual, never submitted.
  List<Polyline> _stopConnectors(List<LatLng> path, LatLng prev, LatLng curr) {
    final dash = StrokePattern.dashed(segments: const [8, 6]);
    return [
      Polyline(
        points: [prev, path.first],
        color: Colors.blueGrey,
        strokeWidth: 2,
        pattern: dash,
      ),
      Polyline(
        points: [path.last, curr],
        color: Colors.blueGrey,
        strokeWidth: 2,
        pattern: dash,
      ),
    ];
  }

  List<Marker> _connectMarkers(_SegSpec highlight) {
    final markers = <Marker>[];
    // Two active endpoints.
    markers.add(_pin(highlight.prev, Colors.green, Icons.play_arrow));
    markers.add(_pin(highlight.curr, Colors.red, Icons.flag));
    // Drawn vertices — numbered, removable via Undo/Clear.
    for (int i = 0; i < _points.length; i++) {
      markers.add(
        Marker(
          point: _points[i],
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.deepPurple,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '${i + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
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

  Marker _pin(LatLng p, Color color, IconData icon, {VoidCallback? onTap}) {
    return Marker(
      point: p,
      width: 34,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
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
                    onPressed: _points.isEmpty ? null : _undoPoint,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
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
                    onPressed: _points.isEmpty ? null : _clearPoints,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
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
        _StepBanner(text: _t.stepReviewSave),
        Expanded(child: _buildReviewMap()),
        _buildReviewSummary(),
        _bottomButton(
          widget.isAppend
              ? _t.saveStops(_sequence.length)
              : _t.createRouteWithStops(_sequence.length),
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
            for (int i = 0; i < _segments.length; i++)
              if (_segments[i].path.length >= 2)
                Polyline(
                  points: _segments[i].path,
                  color: _routeColor,
                  strokeWidth: 5,
                )
              // No geometry (Valhalla down, nothing drawn): schematic dashed
              // line — the backend computes the real road path on save.
              else if (i < _specs.length)
                Polyline(
                  points: [_specs[i].prev, _specs[i].curr],
                  color: _routeColor.withValues(alpha: 0.5),
                  strokeWidth: 3,
                  pattern: StrokePattern.dashed(segments: const [10, 8]),
                ),
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
              '${_nameCtrl.text.trim()}  ·  ${_isLoop ? 'Circular' : 'Line'}',
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

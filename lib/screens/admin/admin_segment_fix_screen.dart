import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/route_stop.dart';
import '../../providers/settings_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/constants/colors.dart';

/// Fix the road of ONE stop's incoming segment (previous stop → this stop).
///
/// A Valhalla suggestion (POST suggest-path) is previewed first. If the
/// suggested road is wrong, the admin taps the map to hand-draw the line:
/// taps become exact vertices joined by straight lines, anchored to the
/// suggestion's first/last road coordinates.
///
/// Save always sends the line on screen (drawn, else the suggestion)
/// verbatim via PATCH `{ waypoints: [...] }` — WYSIWYG. The backend then
/// re-stitches the NEXT stop's segment, so the caller must re-fetch the
/// stop list. Pops `true` after a successful save.
class AdminSegmentFixScreen extends StatefulWidget {
  final RouteStop stop; // the stop whose incoming segment is wrong
  final RouteStop prevStop; // the segment runs prevStop → stop
  final Color routeColor;

  const AdminSegmentFixScreen({
    super.key,
    required this.stop,
    required this.prevStop,
    required this.routeColor,
  });

  @override
  State<AdminSegmentFixScreen> createState() => _AdminSegmentFixScreenState();
}

class _AdminSegmentFixScreenState extends State<AdminSegmentFixScreen> {
  final AdminService _admin = AdminService();
  final MapController _mapController = MapController();

  List<LatLng> _points = [];
  List<LatLng> _preview = [];
  bool _suggesting = false;
  bool _saving = false;

  List<LatLng> get _current => widget.stop.segmentPath ?? const [];

  /// The hand-drawn line: Valhalla's first coord → tapped points → Valhalla's
  /// last coord. Falls back to the raw points when the suggestion is missing.
  List<LatLng> get _manualPath => [
    if (_preview.isNotEmpty) _preview.first,
    ..._points,
    if (_preview.length >= 2) _preview.last,
  ];

  void _onTap(LatLng point) {
    if (_saving) return;
    setState(() => _points = [..._points, point]);
  }

  void _undoPoint() {
    if (_points.isEmpty) return;
    setState(() => _points = _points.sublist(0, _points.length - 1));
  }

  void _clearPoints() {
    setState(() => _points = []);
  }

  Future<void> _suggest() async {
    setState(() => _suggesting = true);
    try {
      final path = await _admin.suggestPath(
        from: widget.prevStop.location,
        to: widget.stop.location,
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

  /// Saves the line currently on screen — hand-drawn when points exist,
  /// otherwise the previewed suggestion — verbatim via PATCH { waypoints }.
  /// (Never PATCH { vias: [] }: an empty via list is a silent no-op on the
  /// backend, which made "re-suggest then save" appear to do nothing.)
  Future<void> _save() async {
    final path = _points.isNotEmpty ? _manualPath : _preview;
    if (path.length < 2) return; // button is disabled in this state anyway
    setState(() => _saving = true);
    try {
      await _admin.updateRouteStop(
        widget.stop.id,
        waypoints: [
          for (final p in path) [p.longitude, p.latitude],
        ],
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = e is AdminApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<SettingsProvider>().t.failedWith(msg)),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _suggest(); // preview the default road right away
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lang = settings.languageCode;
    final t = settings.t;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        title: Text(t.fixRouteFor(widget.stop.localizedStopName(lang))),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primaryColor.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '${widget.prevStop.localizedStopName(lang)} → ${widget.stop.localizedStopName(lang)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _buildMap(),
                _hint(),
              ],
            ),
          ),
          _buildBar(),
        ],
      ),
    );
  }

  Widget _hint() {
    final t = context.read<SettingsProvider>().t;
    final text = _suggesting
        ? t.fetchingSuggestion
        : _points.isNotEmpty
        ? t.manualDrawHint(_points.length)
        : t.wrongRoadDrawHint;
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

  Widget _buildMap() {
    final dash = StrokePattern.dashed(segments: const [8, 6]);
    final active = _points.isEmpty ? _preview : _manualPath;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.stop.location,
        initialZoom: 15,
        onTap: (_, p) => _onTap(p),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'kh_map_app',
        ),
        // Current (stored) segment — grey, what we're replacing.
        if (_current.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(points: _current, color: Colors.grey, strokeWidth: 4),
            ],
          ),
        // Valhalla suggestion — active line, or faint underlay while drawing.
        if (_preview.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _preview,
                color: _points.isEmpty
                    ? widget.routeColor
                    : widget.routeColor.withValues(alpha: 0.3),
                strokeWidth: 5,
              ),
            ],
          ),
        // Hand-drawn replacement line.
        if (_points.isNotEmpty && _manualPath.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _manualPath,
                color: widget.routeColor,
                strokeWidth: 5,
              ),
            ],
          ),
        // Dashed marker↔road connectors (visual only, never submitted).
        if (active.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [widget.prevStop.location, active.first],
                color: Colors.blueGrey,
                strokeWidth: 2,
                pattern: dash,
              ),
              Polyline(
                points: [active.last, widget.stop.location],
                color: Colors.blueGrey,
                strokeWidth: 2,
                pattern: dash,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            _pin(widget.prevStop.location, Colors.green, Icons.play_arrow),
            _pin(widget.stop.location, Colors.red, Icons.flag),
            for (int i = 0; i < _points.length; i++)
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
          ],
        ),
      ],
    );
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

  Widget _buildBar() {
    final t = context.watch<SettingsProvider>().t;
    final busy = _suggesting || _saving;
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
                    onPressed: (_saving || _points.isEmpty) ? null : _undoPoint,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _suggest,
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
                    onPressed: (_saving || _points.isEmpty)
                        ? null
                        : _clearPoints,
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
                onPressed:
                    (busy ||
                        (_points.isEmpty ? _preview : _manualPath).length < 2)
                    ? null
                    : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  _points.isNotEmpty ? t.saveDrawnLine : t.saveSuggestedPath,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

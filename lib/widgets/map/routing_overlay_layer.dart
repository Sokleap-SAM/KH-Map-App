import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/route_plan.dart';

// Navigation line colours — blue border, white fill
const Color _kNavBorder = Color(0xFF1565C0);
const Color _kNavFill = Colors.white;
const Color _kFirstBoardColor = Colors.red;
const Color _kStartColor = Colors.green;
const Color _kDestinationColor = Color(0xFFD32F2F);

// Numbered waypoint colours (1 = origin, intermediate = get-off, last = destination).
const Color _kOriginColor = Color(0xFF22C55E); // emerald
const Color _kAlightColor = _kNavBorder; // blue
const Color _kDestColor = Color(0xFFEF4444); // red

/// Draws the routing overlay for one [RouteOption] (the currently selected tab).
///
/// All legs use the same navigation style: **blue outer / white inner**
///   - Walk legs  → dashed (road-following path from backend's `path` field;
///                falls back to a straight line when absent)
///   - Bus legs   → solid; live segments show a pulsing dot at the board stop
///
/// Numbered waypoint dots are painted on top:
///   - **1** at the origin (green)
///   - **2..N-1** at each bus get-off / alight stop (blue)
///   - **N** at the destination (red)
///
/// Bus board stops keep their existing bus-icon markers — only get-offs and
/// endpoints get numbered, so the sequence reads as the steps the user must
/// take rather than every stop along the way.
///
/// Bus legs are drawn first and walk legs on top, so a dashed walk that shares
/// a road with a bus stays visible (bus shows through the dash gaps).
class RoutingOverlayLayer extends StatefulWidget {
  const RoutingOverlayLayer({super.key, required this.option});

  final RouteOption option;

  @override
  State<RoutingOverlayLayer> createState() => _RoutingOverlayLayerState();
}

class _RoutingOverlayLayerState extends State<RoutingOverlayLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<LatLng> _buildBusPath(RouteSegment seg) {
    if (seg.path.length >= 2) return seg.path;
    final boardAt = seg.boardAt;
    final alightAt = seg.alightAt;
    if (boardAt != null && alightAt != null) {
      return [boardAt.coordinates, alightAt.coordinates];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final segments = option.segments;

    // Bus and walk polylines are kept separate so the dashed walk legs paint ON
    // TOP of the solid bus legs. Where a walk shares a road with a bus, the
    // dashes then stay visible and the bus shows through the gaps — instead of
    // the wider, solid bus hiding the walk entirely.
    final busBorders = <Polyline>[];
    final busFills = <Polyline>[];
    final walkBorders = <Polyline>[];
    final walkFills = <Polyline>[];
    final boardMarkers = <Marker>[];
    final liveBoards = <LatLng>[];
    var firstBusSeen = false;

    // ── Polylines + board markers ────────────────────────────────────────
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.isWalk) {
        // Use road-following path from backend; fall back to straight line.
        List<LatLng> points;
        if (seg.path.length >= 2) {
          points = seg.path;
        } else {
          final from = seg.from;
          final to = seg.to;
          if (from == null || to == null) continue;
          points = [from.coordinates, to.coordinates];
        }

        final dashPattern = StrokePattern.dashed(segments: const [3.0, 8]);

        walkBorders.add(
          Polyline(
            points: points,
            color: const Color.fromARGB(255, 192, 21, 21),
            strokeWidth: 5.0,
            pattern: dashPattern,
            strokeCap: StrokeCap.round,
          ),
        );
        walkFills.add(
          Polyline(
            points: points,
            color: _kNavFill,
            strokeWidth: 2.0,
            pattern: dashPattern,
            strokeCap: StrokeCap.round,
          ),
        );

        // Walking person icon at the walk start point.
        if (seg.from != null) {
          final isFirstPoint = i == 0;
          boardMarkers.add(
            _stopMarker(
              seg.from!.coordinates,
              isFirstPoint ? Icons.my_location : Icons.directions_walk,
              color: isFirstPoint ? _kStartColor : _kNavBorder,
            ),
          );
        }
      } else if (seg.isBus) {
        final boardAt = seg.boardAt;
        final alightAt = seg.alightAt;
        if (boardAt == null || alightAt == null) continue;

        final points = _buildBusPath(seg);

        busBorders.add(
          Polyline(
            points: points,
            color: _kNavBorder,
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        busFills.add(
          Polyline(
            points: points,
            color: _kNavFill,
            strokeWidth: 5,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );

        boardMarkers.add(
          _stopMarker(
            boardAt.coordinates,
            Icons.directions_bus,
            color: firstBusSeen ? _kNavBorder : _kFirstBoardColor,
          ),
        );

        final isLastSegment = i == option.segments.length - 1;
        boardMarkers.add(
          _stopMarker(
            alightAt.coordinates,
            isLastSegment ? Icons.location_on : Icons.flag,
            color: isLastSegment ? _kDestinationColor : _kNavBorder,
          ),
        );
        firstBusSeen = true;

        // Collect live board stops — rendered separately as pulsing dots.
        if (seg.hasLiveEta == true) {
          liveBoards.add(boardAt.coordinates);
        }
      }
    }

    // ── Numbered waypoint dots: origin → each get-off → destination ──────
    final numberedMarkers = <Marker>[];
    if (segments.isNotEmpty) {
      var n = 1;
      // 1: origin (first segment's `from` if walk, else `boardAt`).
      final firstSeg = segments.first;
      final originPoint = firstSeg.isWalk
          ? firstSeg.from?.coordinates
          : firstSeg.boardAt?.coordinates;
      if (originPoint != null) {
        numberedMarkers.add(
          _numberedMarker(originPoint, n++, color: _kOriginColor),
        );
      }

      // 2..N-1: each bus segment's alight stop. If the very last leg is a
      // bus (no trailing walk to a separate destination), that alight IS the
      // destination and gets the destination colour.
      final busSegs = segments.where((s) => s.isBus).toList();
      final lastSeg = segments.last;
      for (var idx = 0; idx < busSegs.length; idx++) {
        final alight = busSegs[idx].alightAt;
        if (alight == null) continue;
        final isFinal = idx == busSegs.length - 1 && !lastSeg.isWalk;
        numberedMarkers.add(
          _numberedMarker(
            alight.coordinates,
            n++,
            color: isFinal ? _kDestColor : _kAlightColor,
          ),
        );
      }

      // N: destination from the trailing walk (the common case).
      if (lastSeg.isWalk && lastSeg.to != null) {
        numberedMarkers.add(
          _numberedMarker(lastSeg.to!.coordinates, n++, color: _kDestColor),
        );
      }
    }

    return Stack(
      children: [
        // Bus legs first (solid), each border below its fill for the outline.
        PolylineLayer(polylines: busBorders),
        PolylineLayer(polylines: busFills),
        // Walk legs on top (dashed) so a walk sharing a road with a bus stays
        // visible — its dashes overlay the bus, which shows through the gaps.
        PolylineLayer(polylines: walkBorders),
        PolylineLayer(polylines: walkFills),
        // Board (bus-icon) markers under the numbered dots
        MarkerLayer(markers: boardMarkers),
        MarkerLayer(markers: numberedMarkers),
        // Pulsing live-bus markers on top of everything
        if (liveBoards.isNotEmpty)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) {
              return MarkerLayer(
                markers: liveBoards
                    .map((pos) => _livePulseMarker(pos, _pulseAnim.value))
                    .toList(),
              );
            },
          ),
      ],
    );
  }

  Marker _numberedMarker(LatLng point, int number, {required Color color}) {
    return Marker(
      point: point,
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 5,
              offset: Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          '$number',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Marker _stopMarker(LatLng point, IconData icon, {Color? color}) {
    final bg = color ?? _kNavBorder;
    return Marker(
      point: point,
      width: 30,
      height: 30,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 15),
      ),
    );
  }

  Marker _livePulseMarker(LatLng point, double pulse) {
    const double maxSize = 48;
    return Marker(
      point: point,
      width: maxSize,
      height: maxSize,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer pulsing ring
            Opacity(
              opacity: 1.0 - pulse, // fades out as it grows
              child: Container(
                width: maxSize * pulse,
                height: maxSize * pulse,
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(80),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Inner solid green dot
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Draws the routing overlay for one [RouteOption] (the currently selected tab).
///
/// All legs use the same navigation style: **blue outer / white inner**
///   - Walk legs  → dashed (road-following path from backend's `path` field;
///                falls back to a straight line when absent)
///   - Bus legs   → solid; live segments show a pulsing dot at the board stop
///
/// Two `PolylineLayer`s are stacked so all borders render below all fills.
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

    final borderPolylines = <Polyline>[];
    final fillPolylines = <Polyline>[];
    final markers = <Marker>[];
    final liveBoards = <LatLng>[];
    var firstBusSeen = false;

    for (var i = 0; i < option.segments.length; i++) {
      final seg = option.segments[i];

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

        final dashPattern = StrokePattern.dashed(segments: const [14, 8]);

        borderPolylines.add(
          Polyline(
            points: points,
            color: _kNavBorder,
            strokeWidth: 7,
            pattern: dashPattern,
            strokeCap: StrokeCap.round,
          ),
        );
        fillPolylines.add(
          Polyline(
            points: points,
            color: _kNavFill,
            strokeWidth: 3.5,
            pattern: dashPattern,
            strokeCap: StrokeCap.round,
          ),
        );

        // Walking person icon at the walk start point.
        if (seg.from != null) {
          final isFirstPoint = i == 0;
          markers.add(
            _stopMarker(seg.from!.coordinates, 
                isFirstPoint ? Icons.my_location : Icons.directions_walk,
                color: isFirstPoint ? _kStartColor : _kNavBorder),
          );
        }
      } else if (seg.isBus) {
        final boardAt = seg.boardAt;
        final alightAt = seg.alightAt;
        if (boardAt == null || alightAt == null) continue;

        final points = _buildBusPath(seg);

        borderPolylines.add(
          Polyline(
            points: points,
            color: _kNavBorder,
            strokeWidth: 9,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );
        fillPolylines.add(
          Polyline(
            points: points,
            color: _kNavFill,
            strokeWidth: 5,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
        );

        markers.add(
          _stopMarker(
            boardAt.coordinates,
            Icons.directions_bus,
            color: firstBusSeen ? _kNavBorder : _kFirstBoardColor,
          ),
        );
        
        final isLastSegment = i == option.segments.length - 1;
        markers.add(_stopMarker(
          alightAt.coordinates, 
          isLastSegment ? Icons.location_on : Icons.flag,
          color: isLastSegment ? _kDestinationColor : _kNavBorder));
        firstBusSeen = true;

        // Collect live board stops — rendered separately as pulsing dots.
        if (seg.hasLiveEta == true) {
          liveBoards.add(boardAt.coordinates);
        }
      }
    }

    return Stack(
      children: [
        // Border polylines first so fills paint on top
        PolylineLayer(polylines: borderPolylines),
        PolylineLayer(polylines: fillPolylines),
        MarkerLayer(markers: markers),
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

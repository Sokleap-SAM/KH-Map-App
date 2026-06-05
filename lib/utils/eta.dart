import 'package:latlong2/latlong.dart';

import '../models/route_stop.dart';

/// Seconds until the bus is expected to reach the stop after [currentStopIndex].
///
/// Returns `null` when the bus is dwelling (speed ≤ 1 km/h) so the UI can
/// render "At stop" instead of a number. Returns `0` once the bus has reached
/// the last stop on the route.
double? etaToNextStopSeconds({
  required LatLng currentPos,
  required double? speedKmh,
  required int currentStopIndex,
  required List<RouteStop> stops,
  int? notDepartingUntilMs,
}) {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (notDepartingUntilMs != null && notDepartingUntilMs > nowMs) {
    return (notDepartingUntilMs - nowMs) / 1000;
  }
  if (currentStopIndex + 1 >= stops.length) return 0;
  if (speedKmh == null || speedKmh <= 1) return null;

  final next = stops[currentStopIndex + 1].location;
  final distMeters = const Distance().as(LengthUnit.Meter, currentPos, next);
  final mps = speedKmh * 1000 / 3600;
  return distMeters / mps;
}

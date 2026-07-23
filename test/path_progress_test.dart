import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:kh_map_app/utils/path_progress.dart';

void main() {
  // A ~1 km east-west path near Phnom Penh (constant latitude), so distances
  // along it are easy to reason about.
  const lat = 11.55;
  final path = <LatLng>[
    const LatLng(lat, 104.900),
    const LatLng(lat, 104.905),
    const LatLng(lat, 104.910),
  ];

  test('returns null for a degenerate path', () {
    expect(projectOntoPath(const LatLng(lat, 104.9), const []), isNull);
    expect(
      projectOntoPath(const LatLng(lat, 104.9), [const LatLng(lat, 104.9)]),
      isNull,
    );
  });

  test('point at the start has fraction 0', () {
    final proj = projectOntoPath(const LatLng(lat, 104.900), path)!;
    expect(proj.fraction, closeTo(0, 0.001));
    expect(proj.distanceMeters, closeTo(0, 1));
  });

  test('point at the end has fraction 1', () {
    final proj = projectOntoPath(const LatLng(lat, 104.910), path)!;
    expect(proj.fraction, closeTo(1, 0.001));
  });

  test('point at the midpoint has fraction ~0.5', () {
    final proj = projectOntoPath(const LatLng(lat, 104.905), path)!;
    expect(proj.fraction, closeTo(0.5, 0.01));
  });

  test('off-path point still projects and reports perpendicular distance', () {
    // Slightly north of the midpoint: ~111 m per 0.001 deg latitude.
    final proj = projectOntoPath(const LatLng(lat + 0.001, 104.905), path)!;
    expect(proj.fraction, closeTo(0.5, 0.02));
    expect(proj.distanceMeters, closeTo(111, 10));
  });

  test('past-the-end point clamps to fraction 1', () {
    final proj = projectOntoPath(const LatLng(lat, 104.920), path)!;
    expect(proj.fraction, closeTo(1, 0.001));
  });
}

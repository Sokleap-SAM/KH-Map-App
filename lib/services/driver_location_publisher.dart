import 'dart:async';
import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'driver_mqtt_publisher.dart';

/// Drives the GPS → MQTT pipeline. Throttles GPS callbacks so we publish
/// no faster than [interval] (brief says ≥ 1 s between publishes; backend
/// silently drops anything tighter).
///
/// Cadence is fixed at 5 s — the brief's 3 s/5 s Wi-Fi/cellular split would
/// need `connectivity_plus`; that's a follow-up.
class DriverLocationPublisher {
  final DriverMqttPublisher publisher;
  Duration interval;

  StreamSubscription<Position>? _gpsSub;
  DateTime _lastPublishAt = DateTime.fromMillisecondsSinceEpoch(0);

  DriverLocationPublisher({
    required this.publisher,
    this.interval = const Duration(seconds: 1),
  });

  bool get isRunning => _gpsSub != null;

  /// Start the publish loop. Caller must ensure publisher.connect() was
  /// already called and that location permission was granted.
  Future<void> start() async {
    if (_gpsSub != null) return;

    LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: interval,
        // Foreground service config left to the host app — flag as a
        // hardening follow-up per driver-frontend-brief.md §5 ("Backgrounding").
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );
    }

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_onPosition, onError: (_) {});
  }

  void _onPosition(Position p) {
    final now = DateTime.now();
    if (now.difference(_lastPublishAt) < interval) return;
    _lastPublishAt = now;

    publisher.publishLocation(
      longitude: p.longitude,
      latitude: p.latitude,
      heading: p.heading,
      speed: p.speed,
      recordedAt: now.toUtc(),
    );
  }

  Future<void> stop() async {
    await _gpsSub?.cancel();
    _gpsSub = null;
  }
}

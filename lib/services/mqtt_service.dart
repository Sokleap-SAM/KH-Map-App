import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt/mqtt_client_factory_stub.dart'
    if (dart.library.io) 'mqtt/mqtt_client_factory_io.dart'
    if (dart.library.html) 'mqtt/mqtt_client_factory_web.dart';
import 'mqtt/mqtt_client_id.dart';

/// A single position update from the broker.
class BusPosition {
  final String tripId;
  final String busId;
  final String routeId;
  final double longitude;
  final double latitude;
  final double heading;
  final double speed;

  /// Absent on driver-sourced positions (`source == 'driver'`) — callers
  /// should keep the last known index rather than assume stop 0.
  final int? currentStopIndex;
  final DateTime recordedAt;

  /// Set on parked-bus messages (`status == 'scheduled'`). The detail card
  /// uses this to display "Departs in ~N min".
  final int? notDepartingUntilMs;

  BusPosition({
    required this.tripId,
    required this.busId,
    required this.routeId,
    required this.longitude,
    required this.latitude,
    required this.heading,
    required this.speed,
    required this.currentStopIndex,
    required this.recordedAt,
    this.notDepartingUntilMs,
  });

  LatLng get location => LatLng(latitude, longitude);

  factory BusPosition.fromJson(Map<String, dynamic> json) {
    return BusPosition(
      tripId: json['tripId'] as String,
      busId: json['busId'] as String,
      routeId: json['routeId'] as String,
      longitude: (json['longitude'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
      heading: (json['heading'] as num?)?.toDouble() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0,
      currentStopIndex: (json['currentStopIndex'] as num?)?.toInt(),
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'] as String)
          : DateTime.now(),
      notDepartingUntilMs: (json['notDepartingUntilMs'] as num?)?.toInt(),
    );
  }
}

typedef PositionHandler = void Function(BusPosition);

/// [json] is null when the backend cleared the retained message (zero-length
/// payload) — i.e. the trip completed or was cancelled.
typedef DetailHandler = void Function(Map<String, dynamic>? json);

/// Process-wide singleton MQTT client managed entirely through console logs.
class MqttService {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttClient? _client;
  Future<void>? _connecting;
  Timer? _retryTimer;

  final Set<String> _activeTopics = {};
  final Map<String, List<PositionHandler>> _handlers = {};
  final Map<String, List<DetailHandler>> _detailHandlers = {};
  final Map<String, List<VoidCallback>> _clearedHandlers = {};

  String _brokerUrl() => dotenv.env['MQTT_URL'] ?? 'ws://10.0.2.2:9001';

  Future<void> _ensureConnected() {
    final c = _client;
    if (c != null &&
        c.connectionStatus?.state == MqttConnectionState.connected) {
      return Future.value();
    }
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final clientId = newMqttClientId('rider');
    final url = _brokerUrl();

    final c = createMqttClient(url, clientId);

    // Must stay well under the load balancer's 60 s idle timeout.
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = false;
    c.onConnected = _onConnected;
    c.onDisconnected = _onDisconnected;
    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    // Assigned before connect() so _onConnected (fired from inside connect)
    // can subscribe every active topic — including on a retry, where no
    // subscribeTo* call is waiting to subscribe afterwards.
    _client = c;
    try {
      await c.connect();
    } catch (e) {
      _client = null;
      c.disconnect();
      rethrow;
    }

    c.updates?.listen(_onMessages);
  }

  /// `autoReconnect` only covers drops after a successful connect. If the
  /// initial connect fails, keep retrying while anything is subscribed —
  /// otherwise the map silently degrades to the 60 s HTTP metadata poll.
  void _connectOrRetry() {
    _ensureConnected().catchError((Object e) {
      debugPrint('MQTT connect to ${_brokerUrl()} failed: $e — retrying in 5s');
      if (_retryTimer?.isActive ?? false) return;
      _retryTimer = Timer(const Duration(seconds: 5), () {
        if (_activeTopics.isNotEmpty) _connectOrRetry();
      });
    });
  }

  void _onConnected() {
    final currentSubscriptions = List<String>.from(_activeTopics);

    for (final topic in currentSubscriptions) {
      _client?.subscribe(topic, MqttQos.atMostOnce);
    }
  }

  void _onDisconnected() {}

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final msg = event.payload as MqttPublishMessage;

      // Zero-length payload = backend cleared the retained message because
      // the trip ended. Must be handled before jsonDecode, which would throw.
      if (msg.payload.message.isEmpty) {
        for (final h in List<DetailHandler>.from(
          _detailHandlers[topic] ?? const <DetailHandler>[],
        )) {
          h(null);
        }
        for (final h in List<VoidCallback>.from(
          _clearedHandlers[topic] ?? const <VoidCallback>[],
        )) {
          h();
        }
        continue;
      }

      final payloadStr = utf8.decode(msg.payload.message);

      final detailHandlers = _detailHandlers[topic];
      if (detailHandlers != null && detailHandlers.isNotEmpty) {
        Map<String, dynamic> json;
        try {
          json = jsonDecode(payloadStr) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        for (final h in List<DetailHandler>.from(detailHandlers)) {
          h(json);
        }
        continue;
      }

      final handlers = _handlers[topic];
      if (handlers == null || handlers.isEmpty) continue;

      BusPosition position;
      try {
        final json = jsonDecode(payloadStr) as Map<String, dynamic>;
        position = BusPosition.fromJson(json);
      } catch (_) {
        continue;
      }

      for (final h in List<PositionHandler>.from(handlers)) {
        h(position);
      }
    }
  }

  /// Subscribe to live positions for [routeId]. [onCleared] fires when the
  /// backend clears the topic's retained message (a trip on it ended); the
  /// topic carries no tripId, so callers should re-check active trips.
  Future<VoidCallback> subscribeToRoute(
    String routeId,
    PositionHandler onPosition, {
    VoidCallback? onCleared,
  }) async {
    final topic = 'transit/route/$routeId/position';

    _activeTopics.add(topic);
    (_handlers[topic] ??= <PositionHandler>[]).add(onPosition);
    if (onCleared != null) {
      (_clearedHandlers[topic] ??= <VoidCallback>[]).add(onCleared);
    }

    try {
      await _ensureConnected();
    } catch (_) {
      // Retries in the background; _onConnected subscribes this topic then.
      _connectOrRetry();
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }

    return () {
      if (onCleared != null) {
        final cleared = _clearedHandlers[topic];
        cleared?.remove(onCleared);
        if (cleared != null && cleared.isEmpty) _clearedHandlers.remove(topic);
      }
      final list = _handlers[topic];
      if (list != null) {
        list.remove(onPosition);

        if (list.isEmpty) {
          _handlers.remove(topic);
          _activeTopics.remove(topic);

          if (_client?.connectionStatus?.state ==
              MqttConnectionState.connected) {
            _client?.unsubscribe(topic);
          }
        }
      }
    };
  }

  /// Subscribe to the retained detail message for [tripId]. Broker is
  /// expected to publish on `transit/trip/<tripId>/detail` with `retain=true`,
  /// so a fresh subscriber gets the last value immediately — no spinner.
  /// [onDetail] receives null when the trip ends (retained message cleared).
  Future<VoidCallback> subscribeToTripDetail(
    String tripId,
    DetailHandler onDetail,
  ) async {
    final topic = 'transit/trip/$tripId/detail';

    _activeTopics.add(topic);
    (_detailHandlers[topic] ??= <DetailHandler>[]).add(onDetail);

    try {
      await _ensureConnected();
    } catch (_) {
      // Retries in the background; _onConnected subscribes this topic then.
      _connectOrRetry();
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
    }

    return () {
      final list = _detailHandlers[topic];
      if (list == null) return;
      list.remove(onDetail);

      if (list.isEmpty) {
        _detailHandlers.remove(topic);
        _activeTopics.remove(topic);
        if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
          _client?.unsubscribe(topic);
        }
      }
    };
  }
}

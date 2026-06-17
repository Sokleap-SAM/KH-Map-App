import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt/mqtt_client_factory_stub.dart'
    if (dart.library.io) 'mqtt/mqtt_client_factory_io.dart'
    if (dart.library.html) 'mqtt/mqtt_client_factory_web.dart';

/// A single position update from the broker.
class BusPosition {
  final String tripId;
  final String busId;
  final String routeId;
  final double longitude;
  final double latitude;
  final double heading;
  final double speed;
  final int currentStopIndex;
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
      currentStopIndex: (json['currentStopIndex'] as num?)?.toInt() ?? 0,
      recordedAt: json['recordedAt'] != null
          ? DateTime.parse(json['recordedAt'] as String)
          : DateTime.now(),
      notDepartingUntilMs: (json['notDepartingUntilMs'] as num?)?.toInt(),
    );
  }
}

typedef PositionHandler = void Function(BusPosition);
typedef DetailHandler = void Function(Map<String, dynamic> json);

/// Process-wide singleton MQTT client managed entirely through console logs.
class MqttService {
  MqttService._();
  static final MqttService instance = MqttService._();

  MqttClient? _client;
  Future<void>? _connecting;

  final Set<String> _activeTopics = {};
  final Map<String, List<PositionHandler>> _handlers = {};
  final Map<String, List<DetailHandler>> _detailHandlers = {};

  String _brokerUrl() => dotenv.env['MQTT_URL'] ?? 'ws://10.0.2.2:9001';

  String _newClientId() =>
      'kh_map_app_${DateTime.now().millisecondsSinceEpoch}';

  Future<void> _ensureConnected() {
    final c = _client;
    if (c != null &&
        c.connectionStatus?.state == MqttConnectionState.connected) {
      return Future.value();
    }
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    final clientId = _newClientId();
    final url = _brokerUrl();

    debugPrint(
      'MqttService: Attempting connection to $url with client ID: $clientId...',
    );

    final c = createMqttClient(url, clientId);

    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = false;
    c.onConnected = _onConnected;
    c.onDisconnected = _onDisconnected;
    c.onAutoReconnect = () {
      debugPrint(
        'MqttService: Connection dropped. Auto-reconnecting to broker...',
      );
    };

    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean();

    try {
      await c.connect();
    } catch (e) {
      debugPrint('MqttService: Connection failed critically: $e');
      c.disconnect();
      rethrow;
    }

    _client = c;
    c.updates?.listen(_onMessages);
  }

  void _onConnected() {
    debugPrint('MqttService: Connected successfully! ✅');

    final currentSubscriptions = List<String>.from(_activeTopics);
    debugPrint(
      'MqttService: Restoring ${currentSubscriptions.length} active route subscriptions...',
    );

    for (final topic in currentSubscriptions) {
      _client?.subscribe(topic, MqttQos.atMostOnce);
      debugPrint('MqttService: Re-subscribed to topic -> $topic');
    }
  }

  void _onDisconnected() {
    debugPrint('MqttService: Disconnected from broker ❌');
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final msg = event.payload as MqttPublishMessage;
      final payloadStr = utf8.decode(msg.payload.message);

      debugPrint('MqttService: Incoming data received on topic [$topic]');

      final detailHandlers = _detailHandlers[topic];
      if (detailHandlers != null && detailHandlers.isNotEmpty) {
        Map<String, dynamic> json;
        try {
          json = jsonDecode(payloadStr) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('MqttService: Failed to parse detail payload on $topic: $e');
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
      } catch (e) {
        debugPrint('MqttService: Failed to parse bad payload on $topic: $e');
        continue;
      }

      for (final h in List<PositionHandler>.from(handlers)) {
        h(position);
      }
    }
  }

  /// Subscribe to live positions for [routeId].
  Future<VoidCallback> subscribeToRoute(
    String routeId,
    PositionHandler onPosition,
  ) async {
    final topic = 'transit/route/$routeId/position';

    _activeTopics.add(topic);
    (_handlers[topic] ??= <PositionHandler>[]).add(onPosition);
    debugPrint('MqttService: Local handler registered for route: $routeId');

    try {
      await _ensureConnected();
    } catch (e) {
      debugPrint(
        'MqttService: Delayed subscription registration. Will retry on reconnect sync. Error: $e',
      );
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint(
        'MqttService: Active subscription request dispatched for topic -> $topic',
      );
    }

    return () {
      final list = _handlers[topic];
      if (list != null) {
        list.remove(onPosition);
        debugPrint('MqttService: Local handler removed for route: $routeId');

        if (list.isEmpty) {
          _handlers.remove(topic);
          _activeTopics.remove(topic);
          debugPrint(
            'MqttService: No remaining active lookups. Tearing down broker channel.',
          );

          if (_client?.connectionStatus?.state ==
              MqttConnectionState.connected) {
            _client?.unsubscribe(topic);
            debugPrint('MqttService: Unsubscribed from broker topic -> $topic');
          }
        }
      }
    };
  }

  /// Subscribe to the retained detail message for [tripId]. Broker is
  /// expected to publish on `transit/trip/<tripId>/detail` with `retain=true`,
  /// so a fresh subscriber gets the last value immediately — no spinner.
  Future<VoidCallback> subscribeToTripDetail(
    String tripId,
    DetailHandler onDetail,
  ) async {
    final topic = 'transit/trip/$tripId/detail';

    _activeTopics.add(topic);
    (_detailHandlers[topic] ??= <DetailHandler>[]).add(onDetail);
    debugPrint('MqttService: Local detail handler registered for trip: $tripId');

    try {
      await _ensureConnected();
    } catch (e) {
      debugPrint(
        'MqttService: Delayed detail subscription. Will retry on reconnect sync. Error: $e',
      );
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _client!.subscribe(topic, MqttQos.atMostOnce);
      debugPrint(
        'MqttService: Active detail subscription dispatched for topic -> $topic',
      );
    }

    return () {
      final list = _detailHandlers[topic];
      if (list == null) return;
      list.remove(onDetail);
      debugPrint('MqttService: Local detail handler removed for trip: $tripId');

      if (list.isEmpty) {
        _detailHandlers.remove(topic);
        _activeTopics.remove(topic);
        if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
          _client?.unsubscribe(topic);
          debugPrint('MqttService: Unsubscribed from detail topic -> $topic');
        }
      }
    };
  }
}

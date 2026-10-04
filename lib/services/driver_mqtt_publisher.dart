import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:mqtt_client/mqtt_client.dart';

import '../models/driver_mqtt_credentials.dart';
import 'mqtt/mqtt_client_factory_stub.dart'
    if (dart.library.io) 'mqtt/mqtt_client_factory_io.dart'
    if (dart.library.html) 'mqtt/mqtt_client_factory_web.dart';
import 'mqtt/mqtt_client_id.dart';

/// Thrown when the broker rejects our credentials (CONNACK error). Caller
/// should re-fetch fresh creds via `DriverService.fetchMqttCredentials` and
/// reconnect — per driver brief "Reconnect behaviour".
class DriverMqttAuthFailure implements Exception {
  final String reason;
  DriverMqttAuthFailure(this.reason);
  @override
  String toString() => 'DriverMqttAuthFailure: $reason';
}

/// Publish-only MQTT client for the driver app, connected to the
/// authenticated driver listener (`wss://driver-mqtt…:443`). Single topic
/// (`driver/<driverId>/location`) is published with QoS 0, retain false.
///
/// That listener denies all subscribes — live positions for display must go
/// through the anonymous rider connection (`MqttService.instance`).
class DriverMqttPublisher {
  DriverMqttCredentials? _creds;
  MqttClient? _client;
  Future<void>? _connecting;

  /// Backend discards any `sequence` ≤ the last one it saw as a replay. Seeding
  /// from wall-clock ms keeps it strictly increasing across reconnects,
  /// credential rotation and app restarts without persisting a counter.
  int _sequence = 0;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect(DriverMqttCredentials creds) async {
    if (_creds?.password == creds.password &&
        _creds?.url == creds.url &&
        isConnected) {
      return;
    }
    await disconnect();
    _creds = creds;
    return _connecting ??= _doConnect().whenComplete(() => _connecting = null);
  }

  Future<void> _doConnect() async {
    final creds = _creds!;
    final clientId = newMqttClientId('driver-${creds.username}');

    final c = createMqttClient(creds.url, clientId);
    // Must stay well under the load balancer's 60 s idle timeout.
    c.keepAlivePeriod = 30;
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = false;

    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillQos(MqttQos.atMostOnce)
        .startClean()
        .authenticateAs(creds.username, creds.password);

    try {
      await c.connect(creds.username, creds.password);
    } catch (e) {
      c.disconnect();
      throw DriverMqttAuthFailure('connect threw: $e');
    }

    final state = c.connectionStatus?.state;
    final returnCode = c.connectionStatus?.returnCode;
    if (state != MqttConnectionState.connected) {
      c.disconnect();
      throw DriverMqttAuthFailure('CONNACK $returnCode');
    }

    _client = c;
  }

  /// Build and publish one location sample. Returns false if not currently
  /// connected (caller should keep trying — auto-reconnect is on).
  bool publishLocation({
    required double longitude,
    required double latitude,
    double? heading,
    double? speed,
    DateTime? recordedAt,
  }) {
    final c = _client;
    final creds = _creds;
    if (c == null || creds == null || !isConnected) return false;

    _sequence = max(_sequence + 1, DateTime.now().millisecondsSinceEpoch);
    final payload = <String, dynamic>{
      'longitude': longitude,
      'latitude': latitude,
      'heading': ?heading,
      'speed': ?speed,
      'recordedAt': (recordedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'sequence': _sequence,
    };

    final builder = MqttClientPayloadBuilder()..addString(jsonEncode(payload));
    c.publishMessage(
      creds.publishTopic,
      MqttQos.atMostOnce,
      builder.payload!,
      retain: false,
    );
    return true;
  }

  Future<void> disconnect() async {
    final c = _client;
    _client = null;
    try {
      c?.disconnect();
    } catch (_) {}
  }
}

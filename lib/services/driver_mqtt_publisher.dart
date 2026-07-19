import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';

import '../models/driver_mqtt_credentials.dart';
import 'mqtt/driver_mqtt_factory_stub.dart'
    if (dart.library.io) 'mqtt/driver_mqtt_factory_io.dart'
    if (dart.library.html) 'mqtt/driver_mqtt_factory_web.dart';

/// Signaled when the broker rejects our credentials (CONNACK error). Caller
/// should re-fetch fresh creds via `DriverService.fetchMqttCredentials` and
/// reconnect — per driver brief "Reconnect behaviour".
class DriverMqttAuthFailure implements Exception {
  final String reason;
  DriverMqttAuthFailure(this.reason);
  @override
  String toString() => 'DriverMqttAuthFailure: $reason';
}

/// Publish-only MQTT client for the driver app. Single topic
/// (`driver/<driverId>/location`) is published with QoS 0, retain false —
/// matches the brief exactly. No subscribes.
class DriverMqttPublisher {
  DriverMqttCredentials? _creds;
  MqttClient? _client;
  Future<void>? _connecting;
  int _sequence = 0;

  /// Fired when CONNACK fails with bad-auth so the caller can re-fetch creds.
  final void Function()? onAuthFailure;

  DriverMqttPublisher({this.onAuthFailure});

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  String _clientId(String driverId) =>
      'driver-$driverId-${DateTime.now().millisecondsSinceEpoch}';

  Future<void> connect(DriverMqttCredentials creds) async {
    if (_creds?.password == creds.password &&
        _creds?.host == creds.host &&
        isConnected) {
      return;
    }
    await disconnect();
    _creds = creds;
    _sequence = 0;
    return _connecting ??= _doConnect().whenComplete(() => _connecting = null);
  }

  Future<void> _doConnect() async {
    final creds = _creds!;
    final clientId = _clientId(creds.username);

    final c = createDriverMqttClient(creds.host, creds.port, clientId);
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
      onAuthFailure?.call();
      throw DriverMqttAuthFailure('connect threw: $e');
    }

    final state = c.connectionStatus?.state;
    final returnCode = c.connectionStatus?.returnCode;
    if (state != MqttConnectionState.connected) {
      c.disconnect();
      onAuthFailure?.call();
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

    final payload = <String, dynamic>{
      'longitude': longitude,
      'latitude': latitude,
      'heading': ?heading,
      'speed': ?speed,
      'recordedAt': (recordedAt ?? DateTime.now().toUtc()).toIso8601String(),
      'sequence': ++_sequence,
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

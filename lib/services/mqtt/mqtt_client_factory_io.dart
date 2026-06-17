import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// VM/mobile/desktop: use [MqttServerClient] over WebSocket.
///
/// When `useWebSocket = true`, `MqttServerClient` builds the WS URL by
/// concatenating `host` and `port`. The scheme (`ws://` or `wss://`) MUST be
/// embedded in the host string — passing a bare hostname yields a malformed
/// URL like `10.0.2.2:9001` and the WebSocket handshake fails.
MqttClient createMqttClient(String url, String clientId) {
  final uri = Uri.parse(url);
  final scheme = uri.scheme.isEmpty ? 'ws' : uri.scheme.toLowerCase();
  final hostOnly = uri.host.isNotEmpty ? uri.host : url;
  final host = '$scheme://$hostOnly';
  final port = uri.hasPort ? uri.port : (scheme == 'wss' ? 443 : 80);

  final client = MqttServerClient.withPort(host, clientId, port);
  client.useWebSocket = true;
  client.secure = scheme == 'wss';
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.logging(on: false);
  return client;
}

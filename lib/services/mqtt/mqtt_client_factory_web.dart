import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// Web: [MqttBrowserClient] uses the browser's WebSocket and accepts the full
/// URL (including path) as the broker address.
///
/// The port must be passed explicitly: the browser connection overwrites the
/// URL's port with `client.port`, which defaults to 1883 — so
/// `wss://host:443` would silently dial `wss://host:1883`.
MqttClient createMqttClient(String url, String clientId) {
  final uri = Uri.parse(url);
  final port = uri.hasPort ? uri.port : (uri.scheme == 'wss' ? 443 : 80);
  final client = MqttBrowserClient.withPort(url, clientId, port);
  client.logging(on: false);
  return client;
}

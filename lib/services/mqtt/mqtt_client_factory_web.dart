import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// Web: [MqttBrowserClient] uses the browser's WebSocket and accepts the full
/// URL (including port and path) as the broker address.
MqttClient createMqttClient(String url, String clientId) {
  final client = MqttBrowserClient(url, clientId);
  client.logging(on: true);
  return client;
}

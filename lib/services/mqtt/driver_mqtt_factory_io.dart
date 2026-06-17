import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Raw TCP MQTT client for the driver publish loop. The driver brief uses
/// `mqtt://host:port` (TLS-upgraded to `mqtts://` in prod) — not the
/// WebSocket transport the rider subscriber uses.
MqttClient createDriverMqttClient(String host, int port, String clientId) {
  final c = MqttServerClient.withPort(host, clientId, port);
  c.useWebSocket = false;
  c.secure = false;
  c.logging(on: false);
  return c;
}

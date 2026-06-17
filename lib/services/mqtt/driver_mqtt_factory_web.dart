import 'package:mqtt_client/mqtt_client.dart';

/// Web builds can't open raw TCP sockets — the driver app is mobile-only.
MqttClient createDriverMqttClient(String host, int port, String clientId) {
  throw UnsupportedError(
    'Driver MQTT publish requires native TCP; not available in web builds.',
  );
}

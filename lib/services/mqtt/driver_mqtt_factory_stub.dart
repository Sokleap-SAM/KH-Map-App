import 'package:mqtt_client/mqtt_client.dart';

MqttClient createDriverMqttClient(String host, int port, String clientId) {
  throw UnsupportedError('Driver MQTT publish not supported on this platform.');
}

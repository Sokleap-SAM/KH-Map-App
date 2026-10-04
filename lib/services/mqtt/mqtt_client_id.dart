import 'dart:math';

final Random _random = Random.secure();

/// MQTT client id unique per *connection*. The broker disconnects an existing
/// session when a second one arrives with the same id, so two devices (or the
/// driver app's two connections) sharing an id would kick each other off in a
/// loop. A random suffix avoids that.
String newMqttClientId(String prefix) {
  final suffix = List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$prefix-$suffix';
}

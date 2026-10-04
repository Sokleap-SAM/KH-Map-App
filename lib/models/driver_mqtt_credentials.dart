class DriverMqttCredentials {
  /// Full broker URL (e.g. `wss://driver-mqtt.kh-map.online:443`). Prefer
  /// this over rebuilding from [host]/[port] so a broker move is a backend
  /// env change, not an app release.
  final String url;
  final String host;
  final int port;
  final String username;
  final String password;
  final String publishTopic;

  const DriverMqttCredentials({
    required this.url,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.publishTopic,
  });

  factory DriverMqttCredentials.fromJson(Map<String, dynamic> json) {
    final host = json['host'] as String;
    final port = (json['port'] as num).toInt();
    final protocol = (json['protocol'] as String?) ?? 'wss';
    return DriverMqttCredentials(
      // Older cached creds / responses may lack `url`.
      url: (json['url'] as String?) ?? '$protocol://$host:$port',
      host: host,
      port: port,
      username: json['username'] as String,
      password: json['password'] as String,
      publishTopic: json['publishTopic'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'publishTopic': publishTopic,
  };
}

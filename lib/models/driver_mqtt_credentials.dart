class DriverMqttCredentials {
  final String host;
  final int port;
  final String username;
  final String password;
  final String publishTopic;

  const DriverMqttCredentials({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.publishTopic,
  });

  factory DriverMqttCredentials.fromJson(Map<String, dynamic> json) {
    return DriverMqttCredentials(
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      username: json['username'] as String,
      password: json['password'] as String,
      publishTopic: json['publishTopic'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'publishTopic': publishTopic,
      };
}

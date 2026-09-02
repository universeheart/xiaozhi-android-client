class XiaozhiConfig {
  final String id;
  final String name;
  final String websocketUrl;
  final String otaUrl;
  final String macAddress;
  final String token;
  final bool enableAutoAuth;

  XiaozhiConfig({
    required this.id,
    required this.name,
    required this.websocketUrl,
    this.otaUrl = '',
    required this.macAddress,
    required this.token,
    this.enableAutoAuth = false,
  });

  factory XiaozhiConfig.fromJson(Map<String, dynamic> json) {
    return XiaozhiConfig(
      id: json['id'],
      name: json['name'],
      websocketUrl: json['websocketUrl'],
      otaUrl: json['otaUrl'] ?? '',
      macAddress: json['macAddress'],
      token: json['token'] ?? '',
      enableAutoAuth: json['enableAutoAuth'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'websocketUrl': websocketUrl,
      'otaUrl': otaUrl,
      'macAddress': macAddress,
      'token': token,
      'enableAutoAuth': enableAutoAuth,
    };
  }

  XiaozhiConfig copyWith({
    String? name,
    String? websocketUrl,
    String? otaUrl,
    String? macAddress,
    String? token,
    bool? enableAutoAuth,
  }) {
    return XiaozhiConfig(
      id: id,
      name: name ?? this.name,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      otaUrl: otaUrl ?? this.otaUrl,
      macAddress: macAddress ?? this.macAddress,
      token: token ?? this.token,
      enableAutoAuth: enableAutoAuth ?? this.enableAutoAuth,
    );
  }
}

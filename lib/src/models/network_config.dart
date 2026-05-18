class NetworkConfig {
  final String baseUrl;
  final String appVersion;
  final String os;
  final String refreshPath;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final bool enableLogging;
  final bool withCredentials;

  const NetworkConfig({
    required this.baseUrl,
    required this.appVersion,
    required this.os,
    this.refreshPath = 'auth/refresh',
    this.connectTimeout = const Duration(seconds: 60),
    this.receiveTimeout = const Duration(seconds: 60),
    this.enableLogging = false,
    this.withCredentials = true,
  });

  String get refreshUrl => baseUrl + refreshPath;
}

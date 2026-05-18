class NetworkHeaderKeys {
  final String contentType;
  final String language;
  final String currency;
  final String accept;
  final String authorization;
  final String version;
  final String os;
  final String keepAlive;

  const NetworkHeaderKeys({
    this.contentType = 'content-type',
    this.language = 'Accept-Language',
    this.currency = 'Accept-Currency',
    this.accept = 'accept',
    this.authorization = 'authorization',
    this.version = 'version',
    this.os = 'os',
    this.keepAlive = 'keep-alive',
  });
}

class NetworkConfig {
  final String baseUrl;
  final String appVersion;
  final String refreshPath;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration idleTimeout;
  final Duration connectionTimeout;
  final bool enableLogging;
  final bool withCredentials;
  final bool includeOsHeader;
  final String? osOverride;
  final bool useBearerTokenPrefix;
  final NetworkHeaderKeys headerKeys;

  const NetworkConfig({
    required this.baseUrl,
    required this.appVersion,
    this.refreshPath = 'auth/refresh',
    this.connectTimeout = const Duration(seconds: 60),
    this.receiveTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 5),
    this.enableLogging = false,
    this.withCredentials = true,
    this.includeOsHeader = true,
    this.osOverride,
    this.useBearerTokenPrefix = true,
    this.headerKeys = const NetworkHeaderKeys(),
  });

  String get refreshUrl => baseUrl + refreshPath;
}

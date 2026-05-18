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

  /// Manually supplied version string.
  /// Ignored when [autoAppVersion] is true (the default).
  final String appVersion;

  /// When true (default), the factory resolves the version automatically
  /// via `PackageInfo.fromPlatform()` and ignores [appVersion].
  final bool autoAppVersion;

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
    this.appVersion = '',
    this.autoAppVersion = true,
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
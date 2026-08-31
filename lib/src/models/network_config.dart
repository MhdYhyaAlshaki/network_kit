/// Enum to specify how the refresh token should be sent in refresh token requests.
enum RefreshTokenSendMethod {
  /// Send refresh token in the request body/data
  body,

  /// Send refresh token in the request headers
  headers,

  /// Send refresh token as query parameters
  parameters,
}

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

typedef RefreshTokenValueDecoder = String? Function(dynamic responseBody);

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
  final bool enableCurlLogging;
  final int curlHistoryLimit;
  final bool printCurlOnRequest;
  final bool printCurlOnError;
  final bool withCredentials;
  final bool includeOsHeader;
  final String? osOverride;
  final bool useBearerTokenPrefix;
  // Enables automatic token refresh flow on unauthorized responses.
  final bool enableRefreshToken;
  // Enables including fcm token in refresh request payload when available.
  final bool enableFcmToken;
  // The key in the response JSON where the access token can be found in the refresh response. Default is 'access_token'.
  final String accessTokenKey;
  // The key in the response JSON where the refresh token can be found in the refresh response. Default is 'refresh_token'.
  final String refreshTokenKey;
  // The key used to send the device Firebase token in refresh request body.
  final String fcmTokenKey;
  // Specifies how the refresh token should be sent in refresh token requests.
  final RefreshTokenSendMethod refreshTokenSendMethod;
  // Optional custom decoder for access token value from refresh response.
  // When provided, this takes priority over key-based extraction.
  final RefreshTokenValueDecoder? accessTokenDecoder;
  // Optional custom decoder for refresh token value from refresh response.
  // When provided, this takes priority over key-based extraction.
  final RefreshTokenValueDecoder? refreshTokenDecoder;
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
    this.enableCurlLogging = false,
    this.curlHistoryLimit = 20,
    this.printCurlOnRequest = true,
    this.printCurlOnError = false,
    this.withCredentials = true,
    this.includeOsHeader = true,
    this.osOverride,
    this.useBearerTokenPrefix = true,
    this.enableRefreshToken = true,
    this.enableFcmToken = true,
    this.accessTokenKey = 'access_token',
    this.refreshTokenKey = 'refresh_token',
    this.fcmTokenKey = 'fcmToken',
    this.refreshTokenSendMethod = RefreshTokenSendMethod.body,
    this.accessTokenDecoder,
    this.refreshTokenDecoder,
    this.headerKeys = const NetworkHeaderKeys(),
  }) : assert(curlHistoryLimit >= 0, 'curlHistoryLimit must not be negative');

  String get refreshUrl => baseUrl + refreshPath;
}

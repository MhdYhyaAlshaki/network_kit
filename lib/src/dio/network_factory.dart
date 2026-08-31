import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:multiple_result/multiple_result.dart' as result;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../cancel_token/cancel_token_service.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/cancel_interceptor.dart';
import '../interceptors/connection_closed_interceptor.dart';
import '../interceptors/curl_logging_interceptor.dart';
import '../interceptors/general_dio_interceptor.dart';
import '../interceptors/language_interceptor.dart';
import '../models/dio_preferences.dart';
import '../models/network_config.dart';
import '../models/network_error.dart';
import '../models/network_events.dart';
import '../models/response_status_code.dart';

// ---------------------------------------------------------------------------
// Request method
// ---------------------------------------------------------------------------

enum NetworkRequestMethod {
  get('GET'),
  post('POST'),
  put('PUT'),
  delete('DELETE');

  final String value;
  const NetworkRequestMethod(this.value);
}

// ---------------------------------------------------------------------------
// Internal registry
// ---------------------------------------------------------------------------

class _FactoryRegistry {
  _FactoryRegistry._();

  static final _FactoryRegistry _instance = _FactoryRegistry._();
  static _FactoryRegistry get instance => _instance;

  static const String defaultKey = '__default__';

  final Map<String, NetworkKitFactory> _factories = {};

  void register(String name, NetworkKitFactory factory) =>
      _factories[name] = factory;

  NetworkKitFactory? get(String name) => _factories[name];

  NetworkKitFactory? remove(String name) => _factories.remove(name);

  void clear() => _factories.clear();
}

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

class NetworkKitFactory {
  final DioPreferences preferences;
  final NetworkConfig config;
  final NetworkEvents events;
  final CancelTokenService cancelTokenService;

  Dio? _cachedDio;
  // Tracks first-time Dio construction to avoid creating multiple instances
  // when several requests arrive concurrently before cache is populated.
  Future<Dio>? _dioFuture;

  NetworkKitFactory._({
    required this.preferences,
    required this.config,
    this.events = const NetworkEvents(),
    required this.cancelTokenService,
  });

  // -------------------------------------------------------------------------
  // Registration
  // -------------------------------------------------------------------------

  /// Registers this factory as the **default** singleton.
  ///
  /// ```dart
  /// NetworkKitFactory.registerAsDefault(
  ///   preferences: ...,
  ///   config: ...,
  ///   cancelTokenService: ...,
  /// );
  ///
  /// // anywhere later:
  /// final dio = await NetworkKitFactory.instance.createDio();
  /// ```
  static NetworkKitFactory registerAsDefault({
    required DioPreferences preferences,
    required NetworkConfig config,
    NetworkEvents events = const NetworkEvents(),
    required CancelTokenService cancelTokenService,
  }) {
    final factory = NetworkKitFactory._(
      preferences: preferences,
      config: config,
      events: events,
      cancelTokenService: cancelTokenService,
    );
    _FactoryRegistry.instance.register(_FactoryRegistry.defaultKey, factory);
    return factory;
  }

  /// Registers this factory under a custom [name].
  ///
  /// Useful when the app talks to more than one backend:
  ///
  /// ```dart
  /// NetworkKitFactory.registerAs(
  ///   'main',
  ///   preferences: ...,
  ///   config: NetworkConfig(baseUrl: 'https://api.acme.com/'),
  ///   cancelTokenService: ...,
  /// );
  ///
  /// NetworkKitFactory.registerAs(
  ///   'cdn',
  ///   preferences: ...,
  ///   config: NetworkConfig(baseUrl: 'https://cdn.acme.com/'),
  ///   cancelTokenService: ...,
  /// );
  ///
  /// // anywhere later:
  /// final dio = await NetworkKitFactory.named('cdn').createDio();
  /// ```
  static NetworkKitFactory registerAs(
    String name, {
    required DioPreferences preferences,
    required NetworkConfig config,
    NetworkEvents events = const NetworkEvents(),
    required CancelTokenService cancelTokenService,
  }) {
    final factory = NetworkKitFactory._(
      preferences: preferences,
      config: config,
      events: events,
      cancelTokenService: cancelTokenService,
    );
    _FactoryRegistry.instance.register(name, factory);
    return factory;
  }

  // -------------------------------------------------------------------------
  // Retrieval
  // -------------------------------------------------------------------------

  /// Returns the **default** singleton factory.
  ///
  /// Throws a [StateError] if [registerAsDefault] has not been called yet.
  static NetworkKitFactory get instance {
    final f = _FactoryRegistry.instance.get(_FactoryRegistry.defaultKey);
    if (f == null) {
      throw StateError(
        'No default NetworkKitFactory has been registered.\n'
        'Call NetworkKitFactory.registerAsDefault(...) during app startup.',
      );
    }
    return f;
  }

  /// Returns the factory registered under [name].
  ///
  /// Throws a [StateError] if no factory with that name exists.
  static NetworkKitFactory named(String name) {
    final f = _FactoryRegistry.instance.get(name);
    if (f == null) {
      throw StateError(
        'No NetworkKitFactory registered under "$name".\n'
        'Call NetworkKitFactory.registerAs("$name", ...) before using NetworkKitFactory.named("$name").',
      );
    }
    return f;
  }

  /// Returns the factory registered under [name], or `null` if absent.
  ///
  /// Prefer this over [named] when the factory may not yet be registered
  /// and you want to handle the missing case yourself.
  static NetworkKitFactory? maybeNamed(String name) =>
      _FactoryRegistry.instance.get(name);

  /// Resolves a factory by optional [factoryName].
  /// - `null` or empty: default [instance]
  /// - non-empty: [named]
  static NetworkKitFactory resolve({String? factoryName}) {
    if (factoryName == null || factoryName.trim().isEmpty) return instance;
    return named(factoryName);
  }

  // -------------------------------------------------------------------------
  // Removal
  // -------------------------------------------------------------------------

  /// Removes the factory registered under [name].
  static void unregister(String name) => _FactoryRegistry.instance.remove(name);

  /// Removes the default factory.
  static void unregisterDefault() =>
      _FactoryRegistry.instance.remove(_FactoryRegistry.defaultKey);

  /// Removes **all** registered factories (default + named).
  ///
  /// Handy in tests to reset state between cases:
  /// ```dart
  /// tearDown(NetworkKitFactory.clearAll);
  /// ```
  static void clearAll() => _FactoryRegistry.instance.clear();

  // -------------------------------------------------------------------------
  // Dio creation
  // -------------------------------------------------------------------------

  Future<Dio> createDio() async {
    final resolvedVersion = await _resolveAppVersion();

    final dio = Dio();

    if (!kIsWeb) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final context = SecurityContext.defaultContext;
        final client = HttpClient(context: context);
        client.idleTimeout = config.idleTimeout;
        client.connectionTimeout = config.connectionTimeout;
        dio.options.headers[config.headerKeys.keepAlive] = 'true';
        dio.options.extra = {'withCredentials': config.withCredentials};
        return client;
      };
    }

    final headers = <String, String>{
      config.headerKeys.contentType: 'application/json',
      config.headerKeys.accept: 'application/json',
      if (preferences.accessToken.isNotEmpty)
        config.headerKeys.authorization:
            config.useBearerTokenPrefix
                ? 'Bearer ${preferences.accessToken}'
                : preferences.accessToken,
      config.headerKeys.version: resolvedVersion,
      if (config.includeOsHeader)
        config.headerKeys.os: _resolveOs().toLowerCase(),
    };

    dio.options = BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      headers: headers,
    );

    final authInterceptor = AuthInterceptor(
      dio: dio,
      preferences: preferences,
      config: config,
      events: events,
      cancelTokenService: cancelTokenService,
    );

    dio.interceptors.add(ConnectionClosedInterceptor(dio));
    dio.interceptors.add(authInterceptor);
    dio.interceptors.add(GeneralInterceptor(events: events));
    dio.interceptors.add(
      LanguageInterceptor(preferences: preferences, config: config),
    );
    dio.interceptors.add(
      CancelInterceptor(
        cancelTokenService: cancelTokenService,
        refreshUrl: config.refreshUrl,
      ),
    );

    if (config.enableCurlLogging) {
      dio.interceptors.add(
        CurlLoggingInterceptor(
          historyLimit: config.curlHistoryLimit,
          printCurlOnRequest: config.printCurlOnRequest,
          printCurlOnError: config.printCurlOnError,
        ),
      );
    }

    if (config.enableLogging) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          responseHeader: false,
          requestBody: true,
          request: true,
          responseBody: true,
        ),
      );
    }

    return dio;
  }

  // -------------------------------------------------------------------------
  // Convenience request helpers
  // -------------------------------------------------------------------------

  /// Returns a Dio instance for an optional [factoryName].
  /// When [factoryName] is null/empty, default factory is used.
  /// Set [useCached] to false to force a fresh Dio creation.
  static Future<Dio> dio({String? factoryName, bool useCached = true}) async {
    final factory = resolve(factoryName: factoryName);
    if (!useCached) return factory.createDio();
    return factory._getOrCreateDio();
  }

  /// Static convenience helper that routes to a factory by optional name.
  static Future<result.Result<Response<dynamic>, NetworkError>> getFrom(
    String path, {
    String? factoryName,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return resolve(factoryName: factoryName).get(
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Static convenience helper that routes to a factory by optional name.
  static Future<result.Result<Response<dynamic>, NetworkError>> postFrom(
    String path, {
    String? factoryName,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return resolve(factoryName: factoryName).post(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Static convenience helper that routes to a factory by optional name.
  static Future<result.Result<Response<dynamic>, NetworkError>> putFrom(
    String path, {
    String? factoryName,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return resolve(factoryName: factoryName).put(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// Static convenience helper that routes to a factory by optional name.
  static Future<result.Result<Response<dynamic>, NetworkError>> deleteFrom(
    String path, {
    String? factoryName,
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return resolve(factoryName: factoryName).delete(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<result.Result<Response<dynamic>, NetworkError>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      NetworkRequestMethod.get,
      path,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<result.Result<Response<dynamic>, NetworkError>> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      NetworkRequestMethod.post,
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<result.Result<Response<dynamic>, NetworkError>> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      NetworkRequestMethod.put,
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  Future<result.Result<Response<dynamic>, NetworkError>> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) {
    return _request(
      NetworkRequestMethod.delete,
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  Future<Dio> _getOrCreateDio() async {
    if (_cachedDio != null) return _cachedDio!;
    if (_dioFuture != null) return _dioFuture!;

    final creating = createDio();
    _dioFuture = creating;
    try {
      final dio = await creating;
      _cachedDio = dio;
      return dio;
    } finally {
      _dioFuture = null;
    }
  }

  Future<result.Result<Response<dynamic>, NetworkError>> _request(
    NetworkRequestMethod method,
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    try {
      final dio = await _getOrCreateDio();
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: (options ?? Options()).copyWith(method: method.value),
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
      );
      return result.Success(response);
    } on DioException catch (e) {
      return result.Error(_mapDioException(e));
    } on FormatException catch (e) {
      return result.Error(ParsingError(message: e.message));
    } on TypeError catch (e) {
      return result.Error(ParsingError(message: e.toString()));
    } catch (e) {
      return result.Error(UnknownNetworkError(message: e.toString()));
    }
  }

  NetworkError _mapDioException(DioException e) {
    final body = e.response?.data;
    final httpStatus = e.response?.statusCode;
    final statusCode = _resolveStatusCode(body, httpStatus);
    final message = _resolveMessage(body, e.message);
    final normalizedStatus = int.tryParse(statusCode ?? '') ?? httpStatus;

    NetworkError build(NetworkError error) => error;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return build(
          TimeoutError(
            message: message,
            statusCode: statusCode,
            httpStatus: httpStatus,
            body: body,
            dioException: e,
          ),
        );
      case DioExceptionType.cancel:
        return build(
          CancelledError(
            message: message,
            statusCode: statusCode,
            httpStatus: httpStatus,
            body: body,
            dioException: e,
          ),
        );
      case DioExceptionType.connectionError:
        return build(
          NetworkConnectionError(
            message: message,
            statusCode: statusCode,
            httpStatus: httpStatus,
            body: body,
            dioException: e,
          ),
        );
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
      case DioExceptionType.badCertificate:
        break;
    }

    if (e.error is SocketException) {
      return build(
        NetworkConnectionError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }

    if (e.error is FormatException || e.error is TypeError) {
      return build(
        ParsingError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }

    if (normalizedStatus == 401) {
      return build(
        UnauthorizedError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }
    if (normalizedStatus == 403) {
      return build(
        ForbiddenError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }
    if (normalizedStatus == 404) {
      return build(
        NotFoundError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }
    if (normalizedStatus != null && normalizedStatus >= 500) {
      return build(
        ServerError(
          message: message,
          statusCode: statusCode,
          httpStatus: httpStatus,
          body: body,
          dioException: e,
        ),
      );
    }

    return build(
      UnknownNetworkError(
        message: message,
        statusCode: statusCode,
        httpStatus: httpStatus,
        body: body,
        dioException: e,
      ),
    );
  }

  String? _resolveStatusCode(dynamic body, int? fallbackHttpStatus) {
    if (body is Map) {
      final raw = DioResponseKey.firstValue(
        DioResponseKey.statusCodeKeys,
        body,
      );
      if (raw != null) return raw.toString();
    }
    return fallbackHttpStatus?.toString();
  }

  String? _resolveMessage(dynamic body, String? fallbackMessage) {
    if (body is Map) {
      final raw = DioResponseKey.firstValue(DioResponseKey.messageKeys, body);
      if (raw != null) return raw.toString();
    }
    return fallbackMessage;
  }

  Future<String> _resolveAppVersion() async {
    if (!config.autoAppVersion) return config.appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return config.appVersion;
    }
  }

  String _resolveOs() {
    if (config.osOverride?.isNotEmpty ?? false) return config.osOverride!;
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

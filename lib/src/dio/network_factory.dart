import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../cancel_token/cancel_token_service.dart';
import '../interceptors/auth_interceptor.dart';
import '../interceptors/cancel_interceptor.dart';
import '../interceptors/connection_closed_interceptor.dart';
import '../interceptors/general_dio_interceptor.dart';
import '../interceptors/language_interceptor.dart';
import '../models/dio_preferences.dart';
import '../models/network_config.dart';
import '../models/network_events.dart';

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
  final Future<String?> Function()? getDeviceToken;

  NetworkKitFactory({
    required this.preferences,
    required this.config,
    this.events = const NetworkEvents(),
    required this.cancelTokenService,
    this.getDeviceToken,
  });

  // -------------------------------------------------------------------------
  // Registration
  // -------------------------------------------------------------------------

  /// Registers this factory as the **default** singleton.
  ///
  /// ```dart
  /// NetworkKitFactory(preferences: ..., config: ..., cancelTokenService: ...)
  ///   .registerAsDefault();
  ///
  /// // anywhere later:
  /// final dio = await NetworkKitFactory.instance.createDio();
  /// ```
  void registerAsDefault() =>
      _FactoryRegistry.instance.register(_FactoryRegistry.defaultKey, this);

  /// Registers this factory under a custom [name].
  ///
  /// Useful when the app talks to more than one backend:
  ///
  /// ```dart
  /// NetworkKitFactory(config: NetworkConfig(baseUrl: 'https://api.acme.com/'), ...)
  ///   .registerAs('main');
  ///
  /// NetworkKitFactory(config: NetworkConfig(baseUrl: 'https://cdn.acme.com/'), ...)
  ///   .registerAs('cdn');
  ///
  /// // anywhere later:
  /// final dio = await NetworkKitFactory.named('cdn').createDio();
  /// ```
  void registerAs(String name) =>
      _FactoryRegistry.instance.register(name, this);

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
        'Call factory.registerAsDefault() during app startup.',
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
        'Call factory.registerAs("$name") before using NetworkKitFactory.named("$name").',
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

  // -------------------------------------------------------------------------
  // Removal
  // -------------------------------------------------------------------------

  /// Removes the factory registered under [name].
  static void unregister(String name) =>
      _FactoryRegistry.instance.remove(name);

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
      getDeviceToken: getDeviceToken,
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
  // Private helpers
  // -------------------------------------------------------------------------

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
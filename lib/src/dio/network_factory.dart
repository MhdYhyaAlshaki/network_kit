import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
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

  Future<Dio> createDio() async {
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
      config.headerKeys.version: config.appVersion,
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

  String _resolveOs() {
    if (config.osOverride?.isNotEmpty ?? false) {
      return config.osOverride!;
    }
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

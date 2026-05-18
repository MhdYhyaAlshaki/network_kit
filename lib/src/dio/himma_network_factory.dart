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

class DioHeaders {
  static const String applicationJson = 'application/json';
  static const String multipartJson = 'multipart/form-data';
  static const String contentType = 'content-type';
  static const String language = 'Accept-Language';
  static const String currency = 'Accept-Currency';
  static const String accept = 'accept';
  static const String authorization = 'authorization';
  static const String version = 'version';
  static const String os = 'os';

  static Map<String, String> get headers => {
    DioHeaders.contentType: DioHeaders.applicationJson,
    DioHeaders.accept: DioHeaders.applicationJson,
  };
}

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
        client.idleTimeout = const Duration(seconds: 30);
        client.connectionTimeout = const Duration(seconds: 5);
        dio.options.headers['keep-alive'] = 'true';
        dio.options.extra = {'withCredentials': config.withCredentials};
        return client;
      };
    }

    final headers =
        DioHeaders.headers..addAll({
          if (preferences.accessToken.isNotEmpty)
            DioHeaders.authorization: 'Bearer ${preferences.accessToken}',
          DioHeaders.version: config.appVersion,
          DioHeaders.os: config.os.toLowerCase(),
        });

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
    dio.interceptors.add(LanguageInterceptor(preferences: preferences));
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
}

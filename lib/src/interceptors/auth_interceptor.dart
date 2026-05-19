import 'dart:async';

import 'package:dio/dio.dart';

import '../cancel_token/cancel_token_service.dart';
import '../models/dio_preferences.dart';
import '../models/network_config.dart';
import '../models/network_events.dart';
import '../models/response_status_code.dart';

class AuthInterceptor extends Interceptor {
  Dio dio;
  final DioPreferences preferences;
  final NetworkConfig config;
  final NetworkEvents events;
  final CancelTokenService? cancelTokenService;

  bool _isRefreshing = false;
  final List<Future<void> Function()> _requestQueue = [];

  AuthInterceptor({
    required this.dio,
    required this.preferences,
    required this.config,
    this.events = const NetworkEvents(),
    this.cancelTokenService,
  });

  String get refreshUrl => config.refreshUrl;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = preferences.accessToken;
    if (token.isNotEmpty) {
      options.headers[config.headerKeys.authorization] =
          config.useBearerTokenPrefix ? 'Bearer $token' : token;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      if (err.response == null) {
        handler.next(err);
        return;
      }

      final rawStatusCode =
          err.response?.data is Map
              ? DioResponseKey.firstValue(
                DioResponseKey.statusCodeKeys,
                err.response!.data as Map,
              )?.toString()
              : null;

      final isUnauthorized = [
        err.response?.statusCode?.toString(),
        rawStatusCode,
      ].any(
        (statusCode) =>
            statusCode == ResponseStatusCode.errorUnauthorized.value ||
            statusCode == ResponseStatusCode.unAuthenticated.value,
      );

      if (!config.enableRefreshToken ||
          !isUnauthorized ||
          preferences.refreshToken.isEmpty) {
        handler.next(err);
        return;
      }

      if (!_isRefreshing) {
        _isRefreshing = true;
        cancelTokenService?.setRefreshing(true);
        try {
          final newTokens = await _refreshToken();
          await preferences.setAccessToken(newTokens.accessToken);
          await preferences.setRefreshToken(newTokens.refreshToken);

          for (final request in _requestQueue.reversed) {
            await request();
          }
          _requestQueue.clear();

          final response = await _retryRequest(err.requestOptions);
          handler.resolve(response);
        } catch (_) {
          _requestQueue.clear();
          final status =
              err.response?.data is Map<String, dynamic>
                  ? ResponseStatusCode.fromMap(
                    err.response!.data as Map<String, dynamic>,
                  )
                  : null;
          final payload = NetworkEventPayload.fromException(
            err,
            status: status,
          );
          await events.onUnauthorized?.call(payload);
          handler.next(err);
        } finally {
          _isRefreshing = false;
          cancelTokenService?.setRefreshing(false);
        }
      } else {
        _requestQueue.add(() async {
          final response = await _retryRequest(err.requestOptions);
          handler.resolve(response);
        });
      }
    } catch (_) {
      handler.next(err);
    }
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions options) {
    return dio.request(
      options.path,
      cancelToken: options.cancelToken,
      options: Options(
        method: options.method,
        headers:
            options.headers
              ..[config.headerKeys.authorization] =
                  config.useBearerTokenPrefix
                      ? 'Bearer ${preferences.accessToken}'
                      : preferences.accessToken,
      ),
      data: _cloneRequestData(options.data),
      onSendProgress: options.onSendProgress,
      queryParameters: options.queryParameters,
    );
  }

  Future<_RefreshedTokens> _refreshToken() async {
    final fcmToken = await preferences.fcmToken;

    final response = await dio.post(
      refreshUrl,
      data: {
        config.refreshTokenKey: preferences.refreshToken,
        if (config.enableFcmToken && (fcmToken?.isNotEmpty ?? false))
          config.fcmTokenKey: fcmToken,
      },
    );

    final code =
        response.data is Map
            ? DioResponseKey.firstValue(
              DioResponseKey.statusCodeKeys,
              response.data as Map,
            )?.toString()
            : null;
    if (code == ResponseStatusCode.errorValidationEntity.value) {
      throw DioException(
        requestOptions: RequestOptions(path: refreshUrl),
        type: DioExceptionType.badResponse,
      );
    }

    return _RefreshedTokens(
      accessToken:
          config.accessTokenDecoder?.call(response.data) ??
          _extractTokenByKey(
            responseBody: response.data,
            tokenKey: config.accessTokenKey,
          ),
      refreshToken:
          config.refreshTokenDecoder?.call(response.data) ??
          _extractTokenByKey(
            responseBody: response.data,
            tokenKey: config.refreshTokenKey,
          ),
    );
  }

  String _extractTokenByKey({
    required dynamic responseBody,
    required String tokenKey,
  }) {
    if (responseBody is! Map) return '';
    final data = DioResponseKey.firstValue(
      DioResponseKey.dataKeys,
      responseBody,
    );
    if (data is Map && data[tokenKey] != null) return data[tokenKey].toString();
    final rootValue = responseBody[tokenKey];
    return rootValue?.toString() ?? '';
  }

  dynamic _cloneRequestData(dynamic data) {
    if (data is FormData) {
      final formData = FormData();
      for (final entry in data.fields) {
        formData.fields.add(MapEntry(entry.key, entry.value));
      }
      for (final entry in data.files) {
        final newFile = entry.value.clone();
        formData.files.add(MapEntry(entry.key, newFile));
      }
      return formData;
    }
    if (data is Map) return Map.from(data);
    return data;
  }
}

class _RefreshedTokens {
  final String accessToken;
  final String refreshToken;

  const _RefreshedTokens({
    required this.accessToken,
    required this.refreshToken,
  });
}

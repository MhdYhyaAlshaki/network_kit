import 'dart:async';

import 'package:dio/dio.dart';

import '../cancel_token/cancel_token_service.dart';
import '../dio/himma_network_factory.dart';
import '../models/dio_preferences.dart';
import '../models/network_config.dart';
import '../models/network_events.dart';
import '../models/response_status_code.dart';

class AuthInterceptor extends Interceptor {
  Dio dio;
  final DioPreferences preferences;
  final NetworkConfig config;
  final NetworkEvents events;
  final Future<String?> Function()? getDeviceToken;
  final CancelTokenService? cancelTokenService;

  bool _isRefreshing = false;
  final List<Future<void> Function()> _requestQueue = [];

  AuthInterceptor({
    required this.dio,
    required this.preferences,
    required this.config,
    this.events = const NetworkEvents(),
    this.getDeviceToken,
    this.cancelTokenService,
  });

  String get refreshUrl => config.refreshUrl;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = preferences.accessToken;
    if (token.isNotEmpty) {
      options.headers[DioHeaders.authorization] = 'Bearer $token';
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

      final isUnauthorized = [
        err.response?.statusCode?.toString(),
        (err.response?.data is Map)
            ? err.response?.data[DioResponseKey.statusCode]?.toString()
            : null,
      ].contains(ResponseStatusCode.errorUnauthorized.value);

      if (!isUnauthorized || preferences.refreshToken.isEmpty) {
        handler.next(err);
        return;
      }

      if (!_isRefreshing) {
        _isRefreshing = true;
        cancelTokenService?.setRefreshing(true);
        try {
          final newTokens = await _refreshToken();
          await preferences.setAccessToken(newTokens['access_token'] ?? '');
          await preferences.setRefreshToken(newTokens['refresh_token'] ?? '');

          for (final request in _requestQueue.reversed) {
            await request();
          }
          _requestQueue.clear();

          final response = await _retryRequest(err.requestOptions);
          handler.resolve(response);
        } catch (_) {
          _requestQueue.clear();
          await events.onUnauthorized?.call();
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
              ..[DioHeaders.authorization] =
                  'Bearer ${preferences.accessToken}',
      ),
      data: _cloneRequestData(options.data),
      onSendProgress: options.onSendProgress,
      queryParameters: options.queryParameters,
    );
  }

  Future<Map<String, String>> _refreshToken() async {
    final String? deviceToken = await getDeviceToken?.call();

    final response = await dio.post(
      refreshUrl,
      data: {
        'refresh_token': preferences.refreshToken,
        if (deviceToken != null) 'fcmToken': deviceToken,
      },
    );

    final code =
        response.data is Map
            ? response.data[DioResponseKey.statusCode]?.toString()
            : null;
    if (code == ResponseStatusCode.errorValidationEntity.value) {
      throw DioException(
        requestOptions: RequestOptions(path: refreshUrl),
        type: DioExceptionType.badResponse,
      );
    }

    final data = (response.data as Map)['data'] as Map?;
    return {
      'access_token': data?['access_token']?.toString() ?? '',
      'refresh_token': data?['refresh_token']?.toString() ?? '',
    };
  }

  dynamic _cloneRequestData(dynamic data) {
    if (data is FormData) {
      final formData = FormData();
      for (final entry in data.fields) {
        formData.fields.add(MapEntry(entry.key, entry.value));
      }
      for (final entry in data.files) {
        final newFile =
            entry.value.clone() ??
            MultipartFile.fromFileSync(
              entry.value.filename ?? '',
              filename: entry.value.filename,
              contentType: entry.value.contentType,
            );
        formData.files.add(MapEntry(entry.key, newFile));
      }
      return formData;
    }
    if (data is Map) return Map.from(data);
    return data;
  }
}

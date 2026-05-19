import 'dart:io';

import 'package:dio/dio.dart';

class ConnectionClosedInterceptor extends Interceptor {
  final Dio dio;
  static const _maxRetries = 3;
  static const _retryKey = 'connectionClosedRetryCount';
  static const _connectionClosedMessage =
      'Connection closed before full header was received';

  ConnectionClosedInterceptor(this.dio);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if ((err.error is DioException &&
            err.error.toString().contains(_connectionClosedMessage)) ||
        err.error is SocketException ||
        err.type == DioExceptionType.unknown ||
        (err.message?.toLowerCase().contains('unknown') ?? false) ||
        (err.message?.toLowerCase().contains(_connectionClosedMessage) ??
            false)) {
      final requestOptions = err.requestOptions;
      final currentRetryCount = _resolveRetryCount(
        requestOptions.extra[_retryKey],
      );
      requestOptions.extra[_retryKey] = currentRetryCount;

      if (currentRetryCount < _maxRetries) {
        final nextRetryCount = currentRetryCount + 1;
        requestOptions.extra[_retryKey] = nextRetryCount;
        final newData = _cloneRequestData(err.requestOptions.data);
        try {
          final response = await dio.fetch(
            requestOptions.copyWith(
              data: newData,
              extra: {...requestOptions.extra, _retryKey: nextRetryCount},
            ),
          );
          return handler.resolve(response);
        } catch (e) {
          if (e is DioException) return handler.next(e);
          return handler.next(
            DioException(
              requestOptions: requestOptions,
              type: DioExceptionType.unknown,
              error: e,
              message: e.toString(),
            ),
          );
        }
      }

      return handler.next(
        err.copyWith(
          message:
              '${err.message ?? 'Request failed'} '
              '(retried $currentRetryCount/$_maxRetries times)',
        ),
      );
    }

    super.onError(err, handler);
  }

  int _resolveRetryCount(Object? rawValue) {
    if (rawValue is int) return rawValue;
    if (rawValue is String) return int.tryParse(rawValue) ?? 0;
    return 0;
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

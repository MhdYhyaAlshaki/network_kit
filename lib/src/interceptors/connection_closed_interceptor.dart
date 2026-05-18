import 'dart:io';

import 'package:dio/dio.dart';

class ConnectionClosedInterceptor extends Interceptor {
  final Dio dio;
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
      final currentRetryCount = (requestOptions.extra[_retryKey] ?? 0) as int;

      if (currentRetryCount < 3) {
        requestOptions.extra[_retryKey] = currentRetryCount + 1;
        final newData = _cloneRequestData(err.requestOptions.data);
        try {
          final response = await dio.fetch(
            requestOptions.copyWith(data: newData),
          );
          return handler.resolve(response);
        } catch (e) {
          return handler.next(e as DioException);
        }
      }
    }

    super.onError(err, handler);
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

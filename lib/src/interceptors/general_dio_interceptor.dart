import 'package:dio/dio.dart';

import '../models/network_events.dart';
import '../models/response_status_code.dart';

class GeneralInterceptor extends Interceptor {
  final NetworkEvents events;

  GeneralInterceptor({this.events = const NetworkEvents()});

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      final statusCode = ResponseStatusCode.fromMap(
        (response.data is Map<String, dynamic>)
            ? response.data as Map<String, dynamic>
            : <String, dynamic>{},
      );

      if ((statusCode?.isError ?? false)) {
        final error = DioException.badResponse(
          requestOptions: RequestOptions(path: response.requestOptions.path),
          response: response,
          statusCode: 400,
        );
        handler.reject(error, true);
        return;
      }

      final rawStatus =
          response.data is Map
              ? response.data[DioResponseKey.statusCode]?.toString()
              : null;
      if ([
            ResponseStatusCode.errorUnauthorized.value,
            ResponseStatusCode.unAuthenticated.value,
          ].contains(rawStatus) ||
          [
            ResponseStatusCode.errorUnauthorized.value,
            ResponseStatusCode.unAuthenticated.value,
          ].contains(response.statusCode?.toString())) {
        await events.onUnauthorized?.call();
      } else if (response.statusCode?.toString() ==
              ResponseStatusCode.oldVersion.value ||
          rawStatus == ResponseStatusCode.oldVersion.value) {
        await events.onOldVersion?.call(_extractLastVersion(response.data));
      } else if (statusCode == ResponseStatusCode.errorNotFound) {
        final error = DioException.badResponse(
          requestOptions: RequestOptions(path: response.requestOptions.path),
          response: response,
          statusCode: 404,
        );
        handler.reject(error, true);
        return;
      }

      if (statusCode == ResponseStatusCode.needToCompleteProfile) {
        await events.onNeedCompleteProfile?.call();
      }
    } catch (_) {}
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final rawStatus =
          err.response?.data is Map
              ? err.response?.data[DioResponseKey.statusCode]?.toString()
              : null;
      if ([
            ResponseStatusCode.errorUnauthorized.value,
            ResponseStatusCode.unAuthenticated.value,
          ].contains(rawStatus) ||
          [
            ResponseStatusCode.errorUnauthorized.value,
            ResponseStatusCode.unAuthenticated.value,
          ].contains(err.response?.statusCode?.toString())) {
        await events.onUnauthorized?.call();
      } else if ([
        err.response?.statusCode?.toString(),
        rawStatus,
      ].contains(ResponseStatusCode.oldVersion.value)) {
        await events.onOldVersion?.call(
          _extractLastVersion(err.response?.data),
        );
      }
    } catch (_) {}

    handler.next(err);
  }

  dynamic _extractLastVersion(dynamic data) {
    if (data is Map) {
      final dynamic nested = data['data'];
      if (nested is Map) {
        return nested['last version'];
      }
    }
    return null;
  }
}

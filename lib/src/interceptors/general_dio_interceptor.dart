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
      final dataMap =
          response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : <String, dynamic>{};

      final status = ResponseStatusCode.fromMap(dataMap);

      if (status is ResponseStatusCode && status.isError) {
        final error = DioException.badResponse(
          requestOptions: RequestOptions(path: response.requestOptions.path),
          response: response,
          statusCode: 400,
        );
        handler.reject(error, true);
        return;
      }

      // Read the raw status code from the body using all registered keys.
      final rawStatus =
          response.data is Map
              ? DioResponseKey.firstValue(
                  DioResponseKey.statusCodeKeys,
                  response.data as Map,
                )?.toString()
              : null;

      final httpStatus = response.statusCode?.toString();

      if (_isUnauthorized(rawStatus, httpStatus)) {
        await events.onUnauthorized?.call();
      } else if (_isOldVersion(rawStatus, httpStatus)) {
        await events.onOldVersion?.call(_extractLastVersion(response.data));
      } else if (status == ResponseStatusCode.errorNotFound) {
        final error = DioException.badResponse(
          requestOptions: RequestOptions(path: response.requestOptions.path),
          response: response,
          statusCode: 404,
        );
        handler.reject(error, true);
        return;
      }

      if (status == ResponseStatusCode.needToCompleteProfile) {
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
              ? DioResponseKey.firstValue(
                  DioResponseKey.statusCodeKeys,
                  err.response!.data as Map,
                )?.toString()
              : null;

      final httpStatus = err.response?.statusCode?.toString();

      if (_isUnauthorized(rawStatus, httpStatus)) {
        await events.onUnauthorized?.call();
      } else if (_isOldVersion(rawStatus, httpStatus)) {
        await events.onOldVersion
            ?.call(_extractLastVersion(err.response?.data));
      }
    } catch (_) {}

    handler.next(err);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool _isUnauthorized(String? rawStatus, String? httpStatus) {
    final codes = [
      ResponseStatusCode.errorUnauthorized.value,
      ResponseStatusCode.unAuthenticated.value,
    ];
    return codes.contains(rawStatus) || codes.contains(httpStatus);
  }

  bool _isOldVersion(String? rawStatus, String? httpStatus) {
    final code = ResponseStatusCode.oldVersion.value;
    return rawStatus == code || httpStatus == code;
  }

  dynamic _extractLastVersion(dynamic data) {
    if (data is Map) {
      // Try all registered data keys to find the nested payload.
      final nested = DioResponseKey.firstValue(
        DioResponseKey.dataKeys,
        data,
      );
      if (nested is Map) return nested['last version'];
    }
    return null;
  }
}
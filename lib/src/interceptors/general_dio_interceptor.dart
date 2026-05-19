import 'package:dio/dio.dart';

import '../models/network_events.dart';
import '../models/response_status_code.dart';

class GeneralInterceptor extends Interceptor {
  final NetworkEvents events;
  static const String _handledEventsKey = 'networkKitHandledEvents';

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
      final eventPayload = NetworkEventPayload.fromResponse(
        response,
        status: status,
      );

      final rawStatus = _extractBodyStatusCode(response.data);

      final httpStatus = response.statusCode?.toString();

      if (_isUnauthorized(rawStatus, httpStatus) &&
          _markEventAsHandled(response.requestOptions, 'unauthorized')) {
        await events.onUnauthorized?.call(eventPayload);
      } else if (_isOldVersion(rawStatus, httpStatus)) {
        if (_markEventAsHandled(response.requestOptions, 'oldVersion')) {
          await events.onOldVersion?.call(eventPayload);
        }
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
        await events.onNeedCompleteProfile?.call(eventPayload);
      }

      if (_isErrorStatus(status)) {
        final error = DioException.badResponse(
          requestOptions: RequestOptions(path: response.requestOptions.path),
          response: response,
          statusCode: 400,
        );
        handler.reject(error, true);
        return;
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
      final dataMap =
          err.response?.data is Map<String, dynamic>
              ? err.response!.data as Map<String, dynamic>
              : <String, dynamic>{};
      final status = ResponseStatusCode.fromMap(dataMap);
      final payload = NetworkEventPayload.fromException(err, status: status);

      final rawStatus = _extractBodyStatusCode(err.response?.data);

      final httpStatus = err.response?.statusCode?.toString();

      if (_isUnauthorized(rawStatus, httpStatus) &&
          _markEventAsHandled(err.requestOptions, 'unauthorized')) {
        await events.onUnauthorized?.call(payload);
      } else if (_isOldVersion(rawStatus, httpStatus)) {
        if (_markEventAsHandled(err.requestOptions, 'oldVersion')) {
          await events.onOldVersion?.call(payload);
        }
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

  bool _isErrorStatus(Object? status) {
    if (status is ResponseStatusCode) return status.isError;
    if (status is CustomStatusCode) return status.isError;
    return false;
  }

  String? _extractBodyStatusCode(dynamic data) {
    if (data is Map) {
      return DioResponseKey.firstValue(
        DioResponseKey.statusCodeKeys,
        data,
      )?.toString();
    }
    return null;
  }

  bool _markEventAsHandled(RequestOptions options, String eventKey) {
    final raw = options.extra[_handledEventsKey];
    final handled =
        raw is Set<String>
            ? raw
            : <String>{if (raw is Iterable) ...raw.whereType<String>()};
    if (handled.contains(eventKey)) return false;
    handled.add(eventKey);
    options.extra[_handledEventsKey] = handled;
    return true;
  }
}

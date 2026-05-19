import 'package:dio/dio.dart';

import 'response_status_code.dart';

class NetworkEventPayload {
  final String? statusCode;
  final String? errorMessage;
  final dynamic body;

  /// Parsed status object from [ResponseStatusCode.fromMap].
  /// Can be [ResponseStatusCode], [CustomStatusCode], or `null`.
  final Object? status;

  const NetworkEventPayload({
    this.statusCode,
    this.errorMessage,
    this.body,
    this.status,
  });

  factory NetworkEventPayload.fromResponse(
    Response<dynamic> response, {
    Object? status,
  }) {
    final body = response.data;
    return NetworkEventPayload(
      statusCode: _resolveStatusCode(
        body: body,
        fallbackHttpStatus: response.statusCode?.toString(),
      ),
      errorMessage: _resolveErrorMessage(body: body),
      body: body,
      status: status,
    );
  }

  factory NetworkEventPayload.fromException(
    DioException exception, {
    Object? status,
  }) {
    final body = exception.response?.data;
    return NetworkEventPayload(
      statusCode: _resolveStatusCode(
        body: body,
        fallbackHttpStatus: exception.response?.statusCode?.toString(),
      ),
      errorMessage: _resolveErrorMessage(
        body: body,
        fallbackMessage: exception.message,
      ),
      body: body,
      status: status,
    );
  }

  static String? _resolveStatusCode({
    required dynamic body,
    String? fallbackHttpStatus,
  }) {
    if (body is Map) {
      final raw = DioResponseKey.firstValue(
        DioResponseKey.statusCodeKeys,
        body,
      );
      if (raw != null) return raw.toString();
    }
    return fallbackHttpStatus;
  }

  static String? _resolveErrorMessage({
    required dynamic body,
    String? fallbackMessage,
  }) {
    if (body is Map) {
      final raw = DioResponseKey.firstValue(DioResponseKey.messageKeys, body);
      if (raw != null) return raw.toString();
    }
    return fallbackMessage;
  }
}

class NetworkEvents {
  final Future<void> Function(NetworkEventPayload event)? onUnauthorized;
  final Future<void> Function(NetworkEventPayload event)? onOldVersion;
  final Future<void> Function(NetworkEventPayload event)? onNeedCompleteProfile;
  final Future<void> Function()? onVpnDetected;

  const NetworkEvents({
    this.onUnauthorized,
    this.onOldVersion,
    this.onNeedCompleteProfile,
    this.onVpnDetected,
  });
}

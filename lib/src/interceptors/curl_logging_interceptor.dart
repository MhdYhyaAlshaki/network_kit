import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class CurlLoggingInterceptor extends Interceptor {
  static final List<String> _history = <String>[];

  final int historyLimit;
  final bool printCurlOnRequest;
  final bool printCurlOnError;

  CurlLoggingInterceptor({
    this.historyLimit = 20,
    this.printCurlOnRequest = true,
    this.printCurlOnError = false,
  }) : assert(historyLimit >= 0, 'historyLimit must not be negative');

  static List<String> get history => List.unmodifiable(_history);

  static void clearHistory() => _history.clear();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final curl = cURLRepresentation(options);
    _save(curl);
    if (printCurlOnRequest) debugPrint(curl);
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final curl = cURLRepresentation(err.requestOptions);
    _save(curl);
    if (printCurlOnError) debugPrint(curl);
    handler.next(err);
  }

  @visibleForTesting
  static String cURLRepresentation(RequestOptions options) {
    try {
      final components = <String>['curl -i'];
      if (options.method.toUpperCase() != 'GET') {
        components.add('-X ${options.method}');
      }

      options.headers.forEach((k, v) {
        components.add('-H "$k: $v"');
      });

      final data = _serializableData(options.data);
      if (data != null) {
        final encodedData = json.encode(data).replaceAll('"', '\\"');
        components.add('-d "$encodedData"');
      }

      components.add('"${options.uri}"');
      return components.join(' \\\n\t');
    } catch (e) {
      debugPrint(e.toString());
      return '';
    }
  }

  static dynamic _serializableData(dynamic data) {
    if (data == null) return null;
    if (data is FormData) return Map.fromEntries(data.fields);
    return data;
  }

  void _save(String curl) {
    if (curl.isEmpty || historyLimit == 0) return;
    _history.add(curl);
    if (_history.length <= historyLimit) return;
    _history.removeRange(0, _history.length - historyLimit);
  }
}

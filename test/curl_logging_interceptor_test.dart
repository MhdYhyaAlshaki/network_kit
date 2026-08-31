import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_kit/network_kit.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class _MockAdapter implements HttpClientAdapter {
  final Object? Function(RequestOptions options)? errorBuilder;

  _MockAdapter.success() : errorBuilder = null;
  _MockAdapter.error(this.errorBuilder);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final error = errorBuilder?.call(options);
    if (error != null) {
      if (error is DioException) throw error;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: error,
      );
    }

    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _TestPreferences implements DioPreferences {
  @override
  String accessToken = '';

  @override
  Future<String?> get fcmToken async => null;

  @override
  String languageCode = 'en';

  @override
  String refreshToken = '';

  @override
  Future<void> setAccessToken(String token) async => accessToken = token;

  @override
  Future<void> setRefreshToken(String token) async => refreshToken = token;
}

void main() {
  setUp(() {
    CurlLoggingInterceptor.clearHistory();
    NetworkKitFactory.clearAll();
  });

  test('GET curl does not include explicit GET method', () {
    final options = RequestOptions(
      path: '/users',
      baseUrl: 'https://example.com/',
      method: 'GET',
      headers: {'accept': 'application/json'},
    );

    final curl = CurlLoggingInterceptor.cURLRepresentation(options);

    expect(curl, startsWith('curl -i'));
    expect(curl, isNot(contains('-X GET')));
    expect(curl, contains('-H "accept: application/json"'));
    expect(curl, contains('"https://example.com/users"'));
  });

  test('POST curl includes method, headers, JSON body, and URL', () {
    final options = RequestOptions(
      path: '/users',
      baseUrl: 'https://example.com/',
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer token',
      },
      data: {'name': 'Ali'},
    );

    final curl = CurlLoggingInterceptor.cURLRepresentation(options);

    expect(curl, contains('-X POST'));
    expect(curl, contains('-H "content-type: application/json"'));
    expect(curl, contains('-H "authorization: Bearer token"'));
    expect(curl, contains('-d "{\\"name\\":\\"Ali\\"}"'));
    expect(curl, contains('"https://example.com/users"'));
  });

  test('FormData curl uses fields without mutating request data', () {
    final formData = FormData.fromMap({'name': 'Ali'});
    final options = RequestOptions(
      path: '/users',
      baseUrl: 'https://example.com/',
      method: 'POST',
      data: formData,
    );

    final curl = CurlLoggingInterceptor.cURLRepresentation(options);

    expect(identical(options.data, formData), isTrue);
    expect(options.data, isA<FormData>());
    expect(formData.fields.single.key, 'name');
    expect(formData.fields.single.value, 'Ali');
    expect(curl, contains('-d "{\\"name\\":\\"Ali\\"}"'));
  });

  test('request logging records curl and trims history to limit', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
    dio.httpClientAdapter = _MockAdapter.success();
    dio.interceptors.add(
      CurlLoggingInterceptor(
        historyLimit: 20,
        printCurlOnRequest: false,
        printCurlOnError: false,
      ),
    );

    for (var i = 0; i < 25; i++) {
      await dio.get('/items/$i');
    }

    expect(CurlLoggingInterceptor.history, hasLength(20));
    expect(CurlLoggingInterceptor.history.first, contains('/items/5'));
    expect(CurlLoggingInterceptor.history.last, contains('/items/24'));
  });

  test(
    'error logging records error curl and prints only when enabled',
    () async {
      final previousDebugPrint = debugPrint;
      final printed = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };

      try {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
        dio.httpClientAdapter = _MockAdapter.error(
          (options) => DioException.connectionError(
            requestOptions: options,
            reason: 'offline',
          ),
        );
        dio.interceptors.add(
          CurlLoggingInterceptor(
            printCurlOnRequest: false,
            printCurlOnError: true,
          ),
        );

        await expectLater(dio.get('/broken'), throwsA(isA<DioException>()));

        expect(CurlLoggingInterceptor.history, hasLength(2));
        expect(printed, hasLength(1));
        expect(printed.single, contains('/broken'));
      } finally {
        debugPrint = previousDebugPrint;
      }
    },
  );

  test('factory wires curl logger separately from pretty logger', () async {
    NetworkKitFactory.registerAsDefault(
      preferences: _TestPreferences(),
      config: const NetworkConfig(
        baseUrl: 'https://example.com/',
        autoAppVersion: false,
        appVersion: 'test',
        enableCurlLogging: true,
        enableLogging: true,
      ),
      cancelTokenService: CancelTokenService(),
    );

    final dio = await NetworkKitFactory.dio();

    expect(
      dio.interceptors.any(
        (interceptor) => interceptor is CurlLoggingInterceptor,
      ),
      isTrue,
    );
    expect(
      dio.interceptors.any((interceptor) => interceptor is PrettyDioLogger),
      isTrue,
    );
  });
}

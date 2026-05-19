import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiple_result/multiple_result.dart' as result;
import 'package:network_kit/network_kit.dart';

class _MockReply {
  final int statusCode;
  final Object? body;

  const _MockReply({required this.statusCode, this.body});
}

typedef _ReplyBuilder = _MockReply Function(RequestOptions options);
typedef _ErrorBuilder = Object Function(RequestOptions options);

class _MockAdapter implements HttpClientAdapter {
  final _ReplyBuilder? _replyBuilder;
  final _ErrorBuilder? _errorBuilder;

  _MockAdapter.success(this._replyBuilder) : _errorBuilder = null;
  _MockAdapter.error(this._errorBuilder) : _replyBuilder = null;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_errorBuilder != null) {
      final thrown = _errorBuilder(options);
      if (thrown is DioException) throw thrown;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: thrown,
        message: thrown.toString(),
      );
    }

    final reply = _replyBuilder!(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.statusCode,
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

Future<void> _registerDefaultFactory() async {
  NetworkKitFactory.registerAsDefault(
    preferences: _TestPreferences(),
    config: const NetworkConfig(
      baseUrl: 'https://example.com/',
      autoAppVersion: false,
      appVersion: 'test',
    ),
    cancelTokenService: CancelTokenService(),
  );
}

void main() {
  setUp(() {
    NetworkKitFactory.clearAll();
    DioResponseKey.resetAll();
    ResponseStatusCode.clearAllCodeOverrides();
    ResponseStatusCode.clearAllCustomCodes();
  });

  test('get/post/put/delete return Success on 2xx', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.success(
      (options) => _MockReply(
        statusCode: 200,
        body: {'method': options.method, 'ok': true},
      ),
    );

    final factory = NetworkKitFactory.instance;

    final getResult = await factory.get('/users');
    final postResult = await factory.post('/users', data: {'name': 'Ali'});
    final putResult = await factory.put('/users/1', data: {'name': 'Omar'});
    final deleteResult = await factory.delete('/users/1');

    expect(getResult, isA<result.Success<Response<dynamic>, NetworkError>>());
    expect(postResult, isA<result.Success<Response<dynamic>, NetworkError>>());
    expect(putResult, isA<result.Success<Response<dynamic>, NetworkError>>());
    expect(
      deleteResult,
      isA<result.Success<Response<dynamic>, NetworkError>>(),
    );
  });

  test('maps timeout DioException to TimeoutError', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.error(
      (options) => DioException.connectionTimeout(
        timeout: const Duration(seconds: 1),
        requestOptions: options,
      ),
    );

    final res = await NetworkKitFactory.instance.get('/timeout');

    expect(res, isA<result.Error<Response<dynamic>, NetworkError>>());
    if (res case result.Error(error: final error)) {
      expect(error, isA<TimeoutError>());
    }
  });

  test('maps cancel DioException to CancelledError', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.error(
      (options) => DioException.requestCancelled(
        requestOptions: options,
        reason: 'user cancelled',
      ),
    );

    final res = await NetworkKitFactory.instance.get('/cancelled');

    if (res case result.Error(error: final error)) {
      expect(error, isA<CancelledError>());
    } else {
      fail('Expected Error result');
    }
  });

  test('maps socket/connection problems to NetworkConnectionError', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.error(
      (options) => DioException.connectionError(
        requestOptions: options,
        reason: 'dns',
        error: const SocketException('Failed host lookup'),
      ),
    );

    final res = await NetworkKitFactory.instance.get('/network');

    if (res case result.Error(error: final error)) {
      expect(error, isA<NetworkConnectionError>());
    } else {
      fail('Expected Error result');
    }
  });

  test('maps HTTP errors using body status code before HTTP status', () async {
    DioResponseKey.setStatusCodeKeys(['code']);
    DioResponseKey.setMessageKeys(['message']);

    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.success(
      (_) => const _MockReply(
        statusCode: 500,
        body: {'code': '401', 'message': 'Body status wins'},
      ),
    );

    final res = await NetworkKitFactory.instance.get('/status-priority');

    if (res case result.Error(error: final error)) {
      expect(error, isA<UnauthorizedError>());
      expect(error.statusCode, '401');
      expect(error.httpStatus, 500);
      expect(error.message, 'Body status wins');
    } else {
      fail('Expected Error result');
    }
  });

  test('maps forbidden/notFound/server status codes', () async {
    Future<NetworkError> callWithStatus(int statusCode) async {
      NetworkKitFactory.clearAll();
      await _registerDefaultFactory();
      final dio = await NetworkKitFactory.dio();
      dio.httpClientAdapter = _MockAdapter.success(
        (_) => _MockReply(
          statusCode: statusCode,
          body: {'status_code': '$statusCode', 'message': 'error'},
        ),
      );
      final res = await NetworkKitFactory.instance.get('/status-$statusCode');
      if (res case result.Error(error: final error)) return error;
      throw StateError('Expected error result for $statusCode');
    }

    expect(await callWithStatus(403), isA<ForbiddenError>());
    expect(await callWithStatus(404), isA<NotFoundError>());
    expect(await callWithStatus(500), isA<ServerError>());
  });

  test('maps format/type issues to ParsingError', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.error(
      (options) => DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: const FormatException('Invalid JSON'),
        message: 'Invalid JSON',
      ),
    );

    final res = await NetworkKitFactory.instance.get('/parsing');

    if (res case result.Error(error: final error)) {
      expect(error, isA<ParsingError>());
    } else {
      fail('Expected Error result');
    }
  });

  test('maps uncategorized issues to UnknownNetworkError', () async {
    await _registerDefaultFactory();
    final dio = await NetworkKitFactory.dio();
    dio.httpClientAdapter = _MockAdapter.error(
      (options) => DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
        error: StateError('boom'),
        message: 'boom',
      ),
    );

    final res = await NetworkKitFactory.instance.get('/unknown');

    if (res case result.Error(error: final error)) {
      expect(error, isA<UnknownNetworkError>());
    } else {
      fail('Expected Error result');
    }
  });

  test('cached dio reused for the same registered factory', () async {
    await _registerDefaultFactory();
    final dio1 = await NetworkKitFactory.dio();
    final dio2 = await NetworkKitFactory.dio();

    expect(identical(dio1, dio2), isTrue);
  });

  test(
    'static dio/getFrom supports nullable or named factory selection',
    () async {
      NetworkKitFactory.registerAsDefault(
        preferences: _TestPreferences(),
        config: const NetworkConfig(
          baseUrl: 'https://example.com/',
          autoAppVersion: false,
          appVersion: 'test',
        ),
        cancelTokenService: CancelTokenService(),
      );

      NetworkKitFactory.registerAs(
        'secondary',
        preferences: _TestPreferences(),
        config: const NetworkConfig(
          baseUrl: 'https://example.com/',
          autoAppVersion: false,
          appVersion: 'test',
        ),
        cancelTokenService: CancelTokenService(),
      );

      final defaultDio = await NetworkKitFactory.dio();
      defaultDio.httpClientAdapter = _MockAdapter.success(
        (_) => const _MockReply(statusCode: 200, body: {'source': 'default'}),
      );

      final secondaryDio = await NetworkKitFactory.dio(
        factoryName: 'secondary',
      );
      secondaryDio.httpClientAdapter = _MockAdapter.success(
        (_) => const _MockReply(statusCode: 200, body: {'source': 'secondary'}),
      );

      final resolvedDefaultDio = await NetworkKitFactory.dio();
      final resolvedNamedDio = await NetworkKitFactory.dio(
        factoryName: 'secondary',
      );

      expect(identical(resolvedDefaultDio, defaultDio), isTrue);
      expect(identical(resolvedNamedDio, secondaryDio), isTrue);

      final defaultResult = await NetworkKitFactory.getFrom('/users');
      final namedResult = await NetworkKitFactory.getFrom(
        '/users',
        factoryName: 'secondary',
      );

      if (defaultResult case result.Success(success: final response)) {
        expect(response.data['source'], 'default');
      } else {
        fail('Expected success from default factory');
      }

      if (namedResult case result.Success(success: final response)) {
        expect(response.data['source'], 'secondary');
      } else {
        fail('Expected success from named factory');
      }
    },
  );
}

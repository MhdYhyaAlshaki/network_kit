import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_kit/network_kit.dart';
import 'package:network_kit/src/interceptors/auth_interceptor.dart';
import 'package:network_kit/src/interceptors/general_dio_interceptor.dart';

class _MockReply {
  final int statusCode;
  final Object? body;

  const _MockReply({required this.statusCode, this.body});
}

typedef _ReplyBuilder = _MockReply Function(RequestOptions options);

class _MockAdapter implements HttpClientAdapter {
  final _ReplyBuilder _replyBuilder;

  _MockAdapter(this._replyBuilder);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final reply = _replyBuilder(options);
    final encoded = jsonEncode(reply.body);
    return ResponseBody.fromString(
      encoded,
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
  String accessToken = 'old_access';

  String? fcmTokenValue;

  @override
  Future<String?> get fcmToken async => fcmTokenValue;

  @override
  String languageCode = 'en';

  @override
  String refreshToken = 'refresh_token';

  @override
  Future<void> setAccessToken(String token) async => accessToken = token;

  @override
  Future<void> setRefreshToken(String token) async => refreshToken = token;
}

void main() {
  setUp(() {
    DioResponseKey.resetAll();
    ResponseStatusCode.clearAllCodeOverrides();
    ResponseStatusCode.clearAllCustomCodes();
  });

  test(
    'general interceptor emits unauthorized payload from error response',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code', 'code']);
      DioResponseKey.setMessageKeys(['message', 'description']);

      NetworkEventPayload? captured;
      var callCount = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter(
        (_) => const _MockReply(
          statusCode: 401,
          body: {'code': '401', 'description': 'Token expired'},
        ),
      );
      dio.interceptors.add(
        GeneralInterceptor(
          events: NetworkEvents(
            onUnauthorized: (event) async {
              captured = event;
              callCount++;
            },
          ),
        ),
      );

      await expectLater(dio.get('/secure'), throwsA(isA<DioException>()));

      expect(callCount, 1);
      expect(captured, isNotNull);
      expect(captured!.statusCode, '401');
      expect(captured!.errorMessage, 'Token expired');
      expect(captured!.body, {'code': '401', 'description': 'Token expired'});
    },
  );

  test(
    'general interceptor emits old-version payload and rejects response',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code']);
      DioResponseKey.setMessageKeys(['message']);

      NetworkEventPayload? captured;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter(
        (_) => const _MockReply(
          statusCode: 200,
          body: {
            'status_code': '426',
            'message': 'Please update the app',
            'data': {'last version': '2.0.0'},
          },
        ),
      );
      dio.interceptors.add(
        GeneralInterceptor(
          events: NetworkEvents(
            onOldVersion: (event) async => captured = event,
          ),
        ),
      );

      await expectLater(
        dio.get('/version-check'),
        throwsA(isA<DioException>()),
      );

      expect(captured, isNotNull);
      expect(captured!.statusCode, '426');
      expect(captured!.errorMessage, 'Please update the app');
      expect(captured!.status, ResponseStatusCode.oldVersion);
    },
  );

  test(
    'general interceptor emits need-complete-profile payload on success flow',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code']);
      DioResponseKey.setMessageKeys(['message']);

      NetworkEventPayload? captured;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter(
        (_) => const _MockReply(
          statusCode: 200,
          body: {'status_code': '202', 'message': 'Complete your profile'},
        ),
      );
      dio.interceptors.add(
        GeneralInterceptor(
          events: NetworkEvents(
            onNeedCompleteProfile: (event) async => captured = event,
          ),
        ),
      );

      final response = await dio.get('/profile');

      expect(response.statusCode, 200);
      expect(captured, isNotNull);
      expect(captured!.statusCode, '202');
      expect(captured!.status, ResponseStatusCode.needToCompleteProfile);
    },
  );

  test('custom status with isError=true is rejected as error path', () async {
    DioResponseKey.setStatusCodeKeys(['status_code']);
    ResponseStatusCode.registerCustomCode(
      const CustomStatusCode(
        name: 'maintenanceMode',
        value: '599',
        isError: true,
      ),
    );

    final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
    dio.httpClientAdapter = _MockAdapter(
      (_) => const _MockReply(
        statusCode: 200,
        body: {'status_code': '599', 'message': 'Maintenance mode'},
      ),
    );
    dio.interceptors.add(GeneralInterceptor());

    await expectLater(dio.get('/maintenance'), throwsA(isA<DioException>()));
  });

  test(
    'auth interceptor emits unauthorized payload when refresh fails',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code', 'code']);
      DioResponseKey.setMessageKeys(['message', 'description']);

      final preferences = _TestPreferences();
      NetworkEventPayload? captured;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter((options) {
        if (options.path.endsWith('auth/refresh')) {
          return const _MockReply(
            statusCode: 200,
            body: {
              'status_code': '422',
              'message': 'Refresh token is invalid',
              'data': {'access_token': '', 'refresh_token': ''},
            },
          );
        }

        return const _MockReply(
          statusCode: 401,
          body: {'code': '401', 'description': 'Access token expired'},
        );
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          preferences: preferences,
          config: const NetworkConfig(
            baseUrl: 'https://example.com/',
            autoAppVersion: false,
            refreshPath: 'auth/refresh',
          ),
          events: NetworkEvents(
            onUnauthorized: (event) async => captured = event,
          ),
        ),
      );

      await expectLater(dio.get('users/me'), throwsA(isA<DioException>()));

      expect(captured, isNotNull);
      expect(captured!.statusCode, '401');
      expect(captured!.errorMessage, 'Access token expired');
      expect(captured!.status, ResponseStatusCode.errorUnauthorized);
    },
  );

  test('auth interceptor uses config decoders for refreshed tokens', () async {
    DioResponseKey.setStatusCodeKeys(['status_code', 'code']);

    final preferences = _TestPreferences();
    var usersMeCount = 0;

    final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
    dio.httpClientAdapter = _MockAdapter((options) {
      if (options.path.endsWith('auth/refresh')) {
        return const _MockReply(
          statusCode: 200,
          body: {
            'status_code': '200',
            'payload': {
              'tokens': {
                'access': 'decoded_access',
                'refresh': 'decoded_refresh',
              },
            },
          },
        );
      }

      if (options.path.endsWith('users/me')) {
        usersMeCount++;
        if (usersMeCount == 1) {
          return const _MockReply(
            statusCode: 401,
            body: {'code': '401', 'message': 'Access token expired'},
          );
        }

        return _MockReply(
          statusCode: 200,
          body: {
            'status_code': '200',
            'authorization': options.headers['authorization'],
          },
        );
      }

      return const _MockReply(statusCode: 404, body: {'status_code': '404'});
    });

    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        preferences: preferences,
        config: NetworkConfig(
          baseUrl: 'https://example.com/',
          autoAppVersion: false,
          refreshPath: 'auth/refresh',
          accessTokenDecoder: (responseBody) {
            if (responseBody is! Map) return null;
            final payload = responseBody['payload'];
            if (payload is! Map) return null;
            final tokens = payload['tokens'];
            if (tokens is! Map) return null;
            return tokens['access']?.toString();
          },
          refreshTokenDecoder: (responseBody) {
            if (responseBody is! Map) return null;
            final payload = responseBody['payload'];
            if (payload is! Map) return null;
            final tokens = payload['tokens'];
            if (tokens is! Map) return null;
            return tokens['refresh']?.toString();
          },
        ),
      ),
    );

    final response = await dio.get('users/me');

    expect(response.statusCode, 200);
    expect(response.data['authorization'], 'Bearer decoded_access');
    expect(preferences.accessToken, 'decoded_access');
    expect(preferences.refreshToken, 'decoded_refresh');
  });

  test(
    'auth interceptor skips refresh when enableRefreshToken is false',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code', 'code']);

      final preferences = _TestPreferences();
      var refreshCalls = 0;

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter((options) {
        if (options.path.endsWith('auth/refresh')) {
          refreshCalls++;
          return const _MockReply(
            statusCode: 200,
            body: {
              'status_code': '200',
              'data': {
                'access_token': 'new_access',
                'refresh_token': 'new_refresh',
              },
            },
          );
        }

        return const _MockReply(
          statusCode: 401,
          body: {'code': '401', 'message': 'Access token expired'},
        );
      });

      dio.interceptors.add(
        AuthInterceptor(
          dio: dio,
          preferences: preferences,
          config: const NetworkConfig(
            baseUrl: 'https://example.com/',
            autoAppVersion: false,
            refreshPath: 'auth/refresh',
            enableRefreshToken: false,
          ),
        ),
      );

      await expectLater(dio.get('users/me'), throwsA(isA<DioException>()));
      expect(refreshCalls, 0);
      expect(preferences.accessToken, 'old_access');
      expect(preferences.refreshToken, 'refresh_token');
    },
  );

  test(
    'auth interceptor does not send fcm token when enableFcmToken is false',
    () async {
      DioResponseKey.setStatusCodeKeys(['status_code', 'code']);

      final preferences = _TestPreferences()..fcmTokenValue = 'fcm_123';
      var usersMeCount = 0;
      Map<String, dynamic>? refreshRequestBody;
      const config = NetworkConfig(
        baseUrl: 'https://example.com/',
        autoAppVersion: false,
        refreshPath: 'auth/refresh',
        enableFcmToken: false,
      );

      final dio = Dio(BaseOptions(baseUrl: 'https://example.com/'));
      dio.httpClientAdapter = _MockAdapter((options) {
        if (options.path.endsWith('auth/refresh')) {
          refreshRequestBody = Map<String, dynamic>.from(options.data as Map);
          return const _MockReply(
            statusCode: 200,
            body: {
              'status_code': '200',
              'data': {
                'access_token': 'new_access',
                'refresh_token': 'new_refresh',
              },
            },
          );
        }

        if (options.path.endsWith('users/me')) {
          usersMeCount++;
          if (usersMeCount == 1) {
            return const _MockReply(
              statusCode: 401,
              body: {'code': '401', 'message': 'expired'},
            );
          }
          return _MockReply(
            statusCode: 200,
            body: {
              'status_code': '200',
              'auth': options.headers['authorization'],
            },
          );
        }

        return const _MockReply(statusCode: 404, body: {'status_code': '404'});
      });

      dio.interceptors.add(
        AuthInterceptor(dio: dio, preferences: preferences, config: config),
      );

      final response = await dio.get('users/me');

      expect(response.statusCode, 200);
      expect(refreshRequestBody, isNotNull);
      expect(refreshRequestBody!.containsKey(config.fcmTokenKey), isFalse);
      expect(
        refreshRequestBody![config.refreshTokenKey],
        equals('refresh_token'),
      );
      expect(preferences.accessToken, 'new_access');
      expect(preferences.refreshToken, 'new_refresh');
    },
  );

  test('onVpnDetected callback remains no-arg API', () async {
    var called = false;
    final events = NetworkEvents(onVpnDetected: () async => called = true);

    await events.onVpnDetected?.call();

    expect(called, isTrue);
  });
}

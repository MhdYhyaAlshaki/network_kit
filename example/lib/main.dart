import 'dart:async';
import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart'; 
import 'package:network_kit_example/network_kit_example_app.dart'; 
import 'package:shared_preferences/shared_preferences.dart';

class AppDioPreferences implements DioPreferences {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _languageCodeKey = 'language_code';
  static const _fcmTokenKey = 'fcm_token';

  final SharedPreferences prefs;

  AppDioPreferences(this.prefs);

  @override
  String get accessToken => prefs.getString(_accessTokenKey) ?? '';

  @override
  String get refreshToken => prefs.getString(_refreshTokenKey) ?? '';

  @override
  String get languageCode => prefs.getString(_languageCodeKey) ?? 'en';

  @override
  Future<String?> get fcmToken async => prefs.getString(_fcmTokenKey);

  @override
  Future<void> setAccessToken(String token) async {
    await prefs.setString(_accessTokenKey, token);
  }

  @override
  Future<void> setRefreshToken(String token) async {
    await prefs.setString(_refreshTokenKey, token);
  }

  Future<void> seedDemoValues() async {
    await prefs.setString(_languageCodeKey, 'en');
    await prefs.setString(_fcmTokenKey, 'demo-fcm-token-123');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final appPreferences = AppDioPreferences(prefs);
  await appPreferences.seedDemoValues();

  DioResponseKey.setStatusCodeKeys(['status_code', 'code', 'statusCode']);
  DioResponseKey.setDataKeys(['data', 'result', 'body']);
  DioResponseKey.setMessageKeys(['message', 'msg', 'description']);

  final cancelTokenService = CancelTokenService();

  NetworkKitFactory.registerAsDefault(
    preferences: appPreferences,
    config: const NetworkConfig(
      baseUrl: 'https://jsonplaceholder.typicode.com/',
      enableLogging: true,
      autoAppVersion: true,
      enableRefreshToken: true,
      enableFcmToken: true,
    ),
    cancelTokenService: cancelTokenService,
    events: NetworkEvents(
      onUnauthorized: (event) async {
        debugPrint(
          '[default] Unauthorized -> status:${event.statusCode} message:${event.errorMessage}',
        );
      },
      onOldVersion: (event) async {
        debugPrint('[default] Old version -> body:${event.body}');
      },
      onNeedCompleteProfile: (event) async {
        debugPrint('[default] Complete profile -> status:${event.statusCode}');
      },
    ),
  );

  NetworkKitFactory.registerAs(
    'secondary',
    preferences: appPreferences,
    config: const NetworkConfig(
      baseUrl: 'https://jsonplaceholder.typicode.com/',
      enableLogging: false,
      autoAppVersion: false,
      appVersion: 'example-1.0.0',
      enableRefreshToken: true,
      enableFcmToken: false,
    ),
    cancelTokenService: cancelTokenService,
    events: NetworkEvents(
      onUnauthorized: (event) async {
        debugPrint(
          '[secondary] Unauthorized -> status:${event.statusCode} message:${event.errorMessage}',
        );
      },
    ),
  );

  runApp(NetworkKitExampleApp(cancelTokenService: cancelTokenService));
}

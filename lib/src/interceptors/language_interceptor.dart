import 'package:dio/dio.dart';

import '../models/dio_preferences.dart';
import '../models/network_config.dart';

class LanguageInterceptor extends Interceptor {
  final DioPreferences preferences;
  final NetworkConfig config;

  LanguageInterceptor({required this.preferences, required this.config});

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers[config.headerKeys.language] = preferences.languageCode;
    super.onRequest(options, handler);
  }
}

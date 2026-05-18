import 'package:dio/dio.dart';

import '../dio/himma_network_factory.dart';
import '../models/dio_preferences.dart';

class LanguageInterceptor extends Interceptor {
  final DioPreferences preferences;

  LanguageInterceptor({required this.preferences});

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    options.headers[DioHeaders.language] = preferences.languageCode;
    super.onRequest(options, handler);
  }
}

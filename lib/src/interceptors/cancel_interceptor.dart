import 'package:dio/dio.dart';

import '../cancel_token/cancel_token_service.dart';

class CancelInterceptor extends Interceptor {
  final CancelTokenService cancelTokenService;
  final String refreshUrl;

  CancelInterceptor({
    required this.cancelTokenService,
    required this.refreshUrl,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if ((options.baseUrl + options.path) != refreshUrl) {
      options.cancelToken = cancelTokenService.getCurrentCancelToken();
    }
    handler.next(options);
  }
}

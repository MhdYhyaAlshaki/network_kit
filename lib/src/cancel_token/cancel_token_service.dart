import 'package:dio/dio.dart';

class CancelTokenService {
  final Map<Object, CancelToken> _cancelTokens = {};
  Object? _currentContext;
  bool _isRefreshing = false;

  void setRefreshing(bool value) {
    _isRefreshing = value;
  }

  CancelToken getOrCreateCancelToken(Object contextKey) {
    _currentContext = contextKey;
    return _cancelTokens.putIfAbsent(contextKey, () => CancelToken());
  }

  CancelToken? getCurrentCancelToken() {
    if (_currentContext == null) return null;
    return _cancelTokens[_currentContext];
  }

  void cancelRequests(Object contextKey) {
    if (_isRefreshing) return;
    final token = _cancelTokens.remove(contextKey);
    if (token != null && !token.isCancelled) {
      token.cancel();
    }
    clearCurrentContext(contextKey);
  }

  void clearCurrentContext(Object contextKey) {
    if (_currentContext == contextKey) {
      _currentContext = null;
    }
  }
}

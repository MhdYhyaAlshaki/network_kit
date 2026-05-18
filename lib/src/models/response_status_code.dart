enum ResponseStatusCode {
  successOk,
  successCreated,
  needToCompleteProfile,
  errorBadRequest,
  errorUnauthorized,
  errorForbidden,
  errorNotFound,
  tooManyRequests,
  errorValidationEntity,
  errorInternalServerError,
  unAuthenticated,
  oldVersion;

  static final Map<ResponseStatusCode, String> _codeOverrides = {};

  static void setCodeOverride(ResponseStatusCode status, String code) {
    _codeOverrides[status] = code;
  }

  static void setCodeOverrides(Map<ResponseStatusCode, String> overrides) {
    _codeOverrides.addAll(overrides);
  }

  static void clearCodeOverride(ResponseStatusCode status) {
    _codeOverrides.remove(status);
  }

  static void clearAllCodeOverrides() {
    _codeOverrides.clear();
  }

  String get value {
    final override = _codeOverrides[this];
    if (override != null) return override;

    switch (this) {
      case ResponseStatusCode.successOk:
        return '200';
      case ResponseStatusCode.successCreated:
        return '201';
      case ResponseStatusCode.needToCompleteProfile:
        return '202';
      case ResponseStatusCode.errorBadRequest:
        return '400';
      case ResponseStatusCode.errorUnauthorized:
        return '401';
      case ResponseStatusCode.errorForbidden:
        return '403';
      case ResponseStatusCode.errorNotFound:
        return '404';
      case ResponseStatusCode.tooManyRequests:
        return '429';
      case ResponseStatusCode.errorValidationEntity:
        return '422';
      case ResponseStatusCode.errorInternalServerError:
        return '500';
      case ResponseStatusCode.unAuthenticated:
        return '401';
      case ResponseStatusCode.oldVersion:
        return '426';
    }
  }

  bool get isError {
    switch (this) {
      case ResponseStatusCode.successOk:
      case ResponseStatusCode.successCreated:
      case ResponseStatusCode.needToCompleteProfile:
      case ResponseStatusCode.errorNotFound:
        return false;
      default:
        return true;
    }
  }

  static ResponseStatusCode? fromMap(Map<String, dynamic> map) {
    final dynamic raw = map[DioResponseKey.statusCode];
    final String? code = raw == null ? null : raw.toString();
    if (code == null) return null;

    for (final status in ResponseStatusCode.values) {
      if (status.value == code) return status;
    }
    return null;
  }
}

class DioResponseKey {
  static const String statusCode = 'status_code';
}

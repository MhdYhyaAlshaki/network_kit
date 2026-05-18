/// Keys used to read fields from the response body map.
///
/// Every field accepts **multiple keys** so the package can handle backends
/// that use different key names across endpoints or versions.
/// Keys are checked in order; the first one that exists in the map wins.
///
/// ```dart
/// // Single key (most common)
/// DioResponseKey.setStatusCodeKeys(['status_code']);
///
/// // Multiple fallback keys — tries 'code' first, then 'status_code'
/// DioResponseKey.setStatusCodeKeys(['code', 'status_code']);
///
/// // Convenience setter for a single key
/// DioResponseKey.setStatusCodeKey('code');
/// ```
class DioResponseKey {
  DioResponseKey._();

  static List<String> _statusCode = ['status_code'];
  static List<String> _data = ['data'];
  static List<String> _message = ['message'];

  // ── Getters (first key = primary) ────────────────────────────────────────

  /// All status-code keys, in priority order.
  static List<String> get statusCodeKeys => List.unmodifiable(_statusCode);

  /// All data keys, in priority order.
  static List<String> get dataKeys => List.unmodifiable(_data);

  /// All message keys, in priority order.
  static List<String> get messageKeys => List.unmodifiable(_message);

  /// Primary (first) status-code key.
  static String get statusCode => _statusCode.first;

  /// Primary (first) data key.
  static String get data => _data.first;

  /// Primary (first) message key.
  static String get message => _message.first;

  // ── Multi-key setters ─────────────────────────────────────────────────────

  /// Replaces the status-code key list.
  ///
  /// ```dart
  /// // Backend sometimes sends 'code', sometimes 'status_code'
  /// DioResponseKey.setStatusCodeKeys(['code', 'status_code']);
  /// ```
  static void setStatusCodeKeys(List<String> keys) {
    assert(keys.isNotEmpty, 'statusCodeKeys must not be empty');
    _statusCode = List.of(keys);
  }

  /// Replaces the data key list.
  static void setDataKeys(List<String> keys) {
    assert(keys.isNotEmpty, 'dataKeys must not be empty');
    _data = List.of(keys);
  }

  /// Replaces the message key list.
  static void setMessageKeys(List<String> keys) {
    assert(keys.isNotEmpty, 'messageKeys must not be empty');
    _message = List.of(keys);
  }

  // ── Single-key convenience setters ───────────────────────────────────────

  /// Replaces the status-code key list with a single [key].
  static void setStatusCodeKey(String key) => setStatusCodeKeys([key]);

  /// Replaces the data key list with a single [key].
  static void setDataKey(String key) => setDataKeys([key]);

  /// Replaces the message key list with a single [key].
  static void setMessageKey(String key) => setMessageKeys([key]);

  // ── Add / remove individual keys ─────────────────────────────────────────

  /// Appends [key] to the status-code key list if not already present.
  static void addStatusCodeKey(String key) {
    if (!_statusCode.contains(key)) _statusCode.add(key);
  }

  /// Appends [key] to the data key list if not already present.
  static void addDataKey(String key) {
    if (!_data.contains(key)) _data.add(key);
  }

  /// Appends [key] to the message key list if not already present.
  static void addMessageKey(String key) {
    if (!_message.contains(key)) _message.add(key);
  }

  /// Removes [key] from the status-code key list.
  /// Does nothing if the list would become empty.
  static void removeStatusCodeKey(String key) {
    if (_statusCode.length > 1) _statusCode.remove(key);
  }

  /// Removes [key] from the data key list.
  /// Does nothing if the list would become empty.
  static void removeDataKey(String key) {
    if (_data.length > 1) _data.remove(key);
  }

  /// Removes [key] from the message key list.
  /// Does nothing if the list would become empty.
  static void removeMessageKey(String key) {
    if (_message.length > 1) _message.remove(key);
  }

  // ── Lookup helper ─────────────────────────────────────────────────────────

  /// Returns the first value found in [map] by iterating [keys] in order,
  /// or `null` if none of the keys are present.
  ///
  /// Used internally by interceptors and [ResponseStatusCode.fromMap].
  ///
  /// ```dart
  /// final code = DioResponseKey.firstValue(DioResponseKey.statusCodeKeys, map);
  /// ```
  static dynamic firstValue(List<String> keys, Map<dynamic, dynamic> map) {
    for (final key in keys) {
      if (map.containsKey(key)) return map[key];
    }
    return null;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Resets all key lists to their built-in defaults.
  static void resetAll() {
    _statusCode = ['status_code'];
    _data = ['data'];
    _message = ['message'];
  }
}

// ---------------------------------------------------------------------------
// CustomStatusCode
// ---------------------------------------------------------------------------

/// Represents a user-defined status code that does not exist in the
/// [ResponseStatusCode] enum.
///
/// ```dart
/// ResponseStatusCode.registerCustomCode(
///   CustomStatusCode(name: 'maintenanceMode', value: '503', isError: true),
/// );
/// ```
class CustomStatusCode {
  final String name;
  final String value;
  final bool isError;

  const CustomStatusCode({
    required this.name,
    required this.value,
    this.isError = false,
  });

  @override
  String toString() => 'CustomStatusCode($name: $value)';

  @override
  bool operator ==(Object other) =>
      other is CustomStatusCode && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

// ---------------------------------------------------------------------------
// ResponseStatusCode
// ---------------------------------------------------------------------------

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

  // ── Built-in value overrides ─────────────────────────────────────────────

  static final Map<ResponseStatusCode, String> _codeOverrides = {};

  static void setCodeOverride(ResponseStatusCode status, String code) =>
      _codeOverrides[status] = code;

  static void setCodeOverrides(Map<ResponseStatusCode, String> overrides) =>
      _codeOverrides.addAll(overrides);

  static void clearCodeOverride(ResponseStatusCode status) =>
      _codeOverrides.remove(status);

  static void clearAllCodeOverrides() => _codeOverrides.clear();

  // ── Custom codes ─────────────────────────────────────────────────────────

  static final Map<String, CustomStatusCode> _customCodes = {};

  static void registerCustomCode(CustomStatusCode code) =>
      _customCodes[code.name] = code;

  static void registerCustomCodes(List<CustomStatusCode> codes) {
    for (final c in codes) {
      _customCodes[c.name] = c;
    }
  }

  static void unregisterCustomCode(String name) => _customCodes.remove(name);

  static void clearAllCustomCodes() => _customCodes.clear();

  static Map<String, CustomStatusCode> get customCodes =>
      Map.unmodifiable(_customCodes);

  // ── Value / isError ──────────────────────────────────────────────────────

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

  // ── Parsing ──────────────────────────────────────────────────────────────

  /// Parses [map] using all registered [DioResponseKey.statusCodeKeys] and
  /// returns the matching [ResponseStatusCode], [CustomStatusCode], or `null`.
  ///
  /// Keys are tried in priority order; the first key present in [map] wins.
  ///
  /// ```dart
  /// final status = ResponseStatusCode.fromMap(response.data);
  ///
  /// if (status is ResponseStatusCode) {
  ///   if (status.isError) { ... }
  /// } else if (status is CustomStatusCode) {
  ///   if (status.name == 'maintenanceMode') { showMaintenance(); }
  /// }
  /// ```
  static Object? fromMap(Map<String, dynamic> map) {
    final raw = DioResponseKey.firstValue(DioResponseKey.statusCodeKeys, map);
    final String? code = raw?.toString();
    if (code == null) return null;

    for (final status in ResponseStatusCode.values) {
      if (status.value == code) return status;
    }
    for (final custom in _customCodes.values) {
      if (custom.value == code) return custom;
    }
    return null;
  }

  /// Returns only a [ResponseStatusCode] from [map], or `null`.
  static ResponseStatusCode? enumFromMap(Map<String, dynamic> map) {
    final result = fromMap(map);
    return result is ResponseStatusCode ? result : null;
  }

  /// Returns only a [CustomStatusCode] from [map], or `null`.
  static CustomStatusCode? customFromMap(Map<String, dynamic> map) {
    final result = fromMap(map);
    return result is CustomStatusCode ? result : null;
  }
}
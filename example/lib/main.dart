import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart';

// ---------------------------------------------------------------------------
// Demo preferences
// ---------------------------------------------------------------------------

class _DemoPreferences implements DioPreferences {
  @override
  String accessToken = '';
  @override
  String refreshToken = '';
  @override
  String languageCode = 'en';

  @override
  Future<void> setAccessToken(String token) async => accessToken = token;
  @override
  Future<void> setRefreshToken(String token) async => refreshToken = token;
}

// ---------------------------------------------------------------------------
// App bootstrap
// ---------------------------------------------------------------------------

void main() {
  // ── 1. Response key configuration ────────────────────────────────────────
  //
  // Supply multiple fallback keys when your backend isn't consistent.
  // Keys are checked in order; the first one present in the response map wins.
  //
  //   Endpoint A returns: { "status_code": "200", "data": {...} }
  //   Endpoint B returns: { "code": "200",         "result": {...} }
  //   Endpoint C returns: { "statusCode": "200",   "body": {...} }
  //
  DioResponseKey.setStatusCodeKeys(['status_code', 'code', 'statusCode']);
  DioResponseKey.setDataKeys(['data', 'result', 'body']);
  DioResponseKey.setMessageKeys(['message', 'msg', 'description']);

  // ── 2. Override built-in status code values ──────────────────────────────
  ResponseStatusCode.setCodeOverrides({
    ResponseStatusCode.needToCompleteProfile: '299',
    ResponseStatusCode.oldVersion: '499',
  });

  // ── 3. Register custom status codes ─────────────────────────────────────
  ResponseStatusCode.registerCustomCodes([
    CustomStatusCode(name: 'maintenanceMode', value: '503', isError: true),
    CustomStatusCode(name: 'pendingVerification', value: '202', isError: false),
  ]);

  // ── 4. Register factories ────────────────────────────────────────────────
  NetworkKitFactory(
    preferences: _DemoPreferences(),
    config: const NetworkConfig(
      baseUrl: 'https://jsonplaceholder.typicode.com/',
      enableLogging: true,
    ),
    events: NetworkEvents(
      onUnauthorized: () async => debugPrint('[main] Unauthorized'),
      onOldVersion: (p) async => debugPrint('[main] Old version: $p'),
    ),
    cancelTokenService: CancelTokenService(),
  ).registerAsDefault();

  NetworkKitFactory(
    preferences: _DemoPreferences(),
    config: const NetworkConfig(
      baseUrl: 'https://dummyjson.com/',
      enableLogging: false,
      autoAppVersion: false,
      appVersion: '0.0.0-secondary',
    ),
    events: const NetworkEvents(),
    cancelTokenService: CancelTokenService(),
  ).registerAs('secondary');

  runApp(const NetworkKitExampleApp());
}

// ---------------------------------------------------------------------------
// App widget
// ---------------------------------------------------------------------------

class NetworkKitExampleApp extends StatelessWidget {
  const NetworkKitExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'network_kit example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const ExampleHomePage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Home page
// ---------------------------------------------------------------------------

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  late final NetworkInfoImplementer _networkInfo;

  Dio? _primaryDio;
  Dio? _secondaryDio;

  String _status = 'Idle';
  bool _connected = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _initDios();
    _listenConnectivity();
  }

  Future<void> _initDios() async {
    final primary = await NetworkKitFactory.instance.createDio();
    final secondary = await NetworkKitFactory.named('secondary').createDio();
    if (!mounted) return;
    setState(() {
      _primaryDio = primary;
      _secondaryDio = secondary;
    });
  }

  void _listenConnectivity() {
    _networkInfo = NetworkInfoImplementer(
      Connectivity(),
      events: NetworkEvents(
        onVpnDetected: () async => _setStatus('VPN detected'),
      ),
    );
    _connectivitySub =
        _networkInfo.onNetworkStatusChanged.listen((online) {
      if (mounted) setState(() => _connected = online);
    });
    _networkInfo.isConnected.then((online) {
      if (mounted) setState(() => _connected = online);
    });
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  // ── Requests ──────────────────────────────────────────────────────────────

  Future<void> _requestPrimary() async {
    if (_primaryDio == null) return;
    final token = NetworkKitFactory.instance.cancelTokenService
        .getOrCreateCancelToken(this);
    _setStatus('Primary request started…');
    try {
      final res = await _primaryDio!.get('posts/1', cancelToken: token);
      _handleResponse(res, prefix: 'Primary');
    } on DioException catch (e) {
      _setStatus(CancelToken.isCancel(e)
          ? 'Primary cancelled'
          : 'Primary error: ${e.message}');
    }
  }

  Future<void> _requestSecondary() async {
    if (_secondaryDio == null) return;
    final token = NetworkKitFactory.named('secondary').cancelTokenService
        .getOrCreateCancelToken(this);
    _setStatus('Secondary request started…');
    try {
      final res = await _secondaryDio!.get('products/1', cancelToken: token);
      _handleResponse(res, prefix: 'Secondary');
    } on DioException catch (e) {
      _setStatus(CancelToken.isCancel(e)
          ? 'Secondary cancelled'
          : 'Secondary error: ${e.message}');
    }
  }

  void _handleResponse(Response res, {required String prefix}) {
    final dataMap = res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : <String, dynamic>{};

    final status = ResponseStatusCode.fromMap(dataMap);

    if (status is ResponseStatusCode) {
      _setStatus('$prefix ✓ ${res.statusCode} — '
          '${status.name} (${status.value}, isError: ${status.isError})');
    } else if (status is CustomStatusCode) {
      _setStatus('$prefix ✓ ${res.statusCode} — '
          'custom:${status.name} (${status.value}, isError: ${status.isError})');
    } else {
      _setStatus('$prefix ✓ HTTP ${res.statusCode}');
    }
  }

  void _cancelAll() {
    NetworkKitFactory.instance.cancelTokenService.cancelRequests(this);
    NetworkKitFactory.named('secondary').cancelTokenService.cancelRequests(this);
    _setStatus('All requests cancelled');
  }

  // ── Key demo ──────────────────────────────────────────────────────────────

  bool _keysExpanded = false;

  void _addStatusKey() {
    DioResponseKey.addStatusCodeKey('statusCode');
    _setStatus(
        'statusCodeKeys: ${DioResponseKey.statusCodeKeys}');
  }

  void _removeStatusKey() {
    DioResponseKey.removeStatusCodeKey('statusCode');
    _setStatus(
        'statusCodeKeys: ${DioResponseKey.statusCodeKeys}');
  }

  void _resetKeys() {
    DioResponseKey.resetAll();
    _setStatus(
      'Keys reset — statusCode: ${DioResponseKey.statusCodeKeys}, '
      'data: ${DioResponseKey.dataKeys}',
    );
  }

  // ── Custom code demo ──────────────────────────────────────────────────────

  bool _customRegistered = true;

  void _toggleCustomCode() {
    if (_customRegistered) {
      ResponseStatusCode.unregisterCustomCode('maintenanceMode');
      _setStatus('Custom "maintenanceMode" unregistered');
    } else {
      ResponseStatusCode.registerCustomCode(
        CustomStatusCode(name: 'maintenanceMode', value: '503', isError: true),
      );
      _setStatus('Custom "maintenanceMode" (503) re-registered');
    }
    setState(() => _customRegistered = !_customRegistered);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _networkInfo.dispose();
    NetworkKitFactory.instance.cancelTokenService.cancelRequests(this);
    NetworkKitFactory.named('secondary').cancelTokenService.cancelRequests(this);
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _primaryDio != null && _secondaryDio != null;

    return Scaffold(
      appBar: AppBar(title: const Text('network_kit example')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ConnectivityBanner(connected: _connected),
            const SizedBox(height: 16),

            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                      ready ? _status : 'Initialising…',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Key info card
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Active DioResponseKey lists',
                        style: theme.textTheme.labelSmall),
                    const SizedBox(height: 6),
                    _KeyRow('statusCode', DioResponseKey.statusCodeKeys),
                    _KeyRow('data', DioResponseKey.dataKeys),
                    _KeyRow('message', DioResponseKey.messageKeys),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _SectionLabel('Requests'),
            FilledButton.icon(
              onPressed: ready ? _requestPrimary : null,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('GET /posts/1  (default factory)'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: ready ? _requestSecondary : null,
              icon: const Icon(Icons.storage_outlined),
              label: const Text('GET /products/1  (named "secondary")'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _cancelAll,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel all'),
            ),

            const SizedBox(height: 24),
            _SectionLabel('DioResponseKey — multi-key demo'),
            OutlinedButton.icon(
              onPressed: () => setState(_addStatusKey),
              icon: const Icon(Icons.add),
              label: const Text('Add "statusCode" to statusCode keys'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(_removeStatusKey),
              icon: const Icon(Icons.remove),
              label: const Text('Remove "statusCode" from statusCode keys'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(_resetKeys),
              icon: const Icon(Icons.refresh),
              label: const Text('Reset all keys to defaults'),
            ),

            const SizedBox(height: 24),
            _SectionLabel('Custom status codes'),
            OutlinedButton.icon(
              onPressed: () => setState(_toggleCustomCode),
              icon: const Icon(Icons.tune),
              label: Text(
                _customRegistered
                    ? 'Unregister "maintenanceMode" (503)'
                    : 'Re-register "maintenanceMode" (503)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? Colors.green : Colors.red;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(connected ? Icons.wifi : Icons.wifi_off, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            connected ? 'Connected' : 'Offline',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow(this.label, this.keys);
  final String label;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
          ),
          Expanded(
            child: Text(
              keys.map((k) => '"$k"').join('  →  '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
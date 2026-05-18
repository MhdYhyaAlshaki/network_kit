import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart';

void main() {
  runApp(const NetworkKitExampleApp());
}

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

class _DemoPreferences implements DioPreferences {
  @override
  String accessToken = '';

  @override
  String refreshToken = '';

  @override
  String languageCode = 'en';

  @override
  Future<void> setAccessToken(String token) async {
    accessToken = token;
  }

  @override
  Future<void> setRefreshToken(String token) async {
    refreshToken = token;
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  final CancelTokenService _cancelTokenService = CancelTokenService();
  late final NetworkInfoImplementer _networkInfo;
  late final Dio _dio;

  String _status = 'Idle';
  bool _connected = true;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _setupNetworking();
    _listenConnectivity();
  }

  Future<void> _setupNetworking() async {
    final factory = NetworkKitFactory(
      preferences: _DemoPreferences(),
      config: const NetworkConfig(
        baseUrl: 'https://jsonplaceholder.typicode.com/',
        appVersion: '1.0.0',
        os: 'android',
        enableLogging: true,
      ),
      events: NetworkEvents(
        onUnauthorized: () async => _setStatus('Unauthorized (401)'),
        onOldVersion: (payload) async => _setStatus('Old version: $payload'),
        onNeedCompleteProfile:
            () async => _setStatus('Need to complete profile'),
        onVpnDetected: () async => _setStatus('VPN detected'),
      ),
      cancelTokenService: _cancelTokenService,
    );

    _dio = await factory.createDio();
  }

  void _listenConnectivity() {
    _networkInfo = NetworkInfoImplementer(
      Connectivity(),
      events: NetworkEvents(
        onVpnDetected: () async => _setStatus('VPN detected by NetworkInfo'),
      ),
    );

    _connectivitySub = _networkInfo.onNetworkStatusChanged.listen((isOnline) {
      setState(() => _connected = isOnline);
    });

    _networkInfo.isConnected.then((isOnline) {
      if (mounted) {
        setState(() => _connected = isOnline);
      }
    });
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  Future<void> _makeRequest() async {
    final cancelToken = _cancelTokenService.getOrCreateCancelToken(this);
    _setStatus('Request started...');

    try {
      final response = await _dio.get('posts/1', cancelToken: cancelToken);
      _setStatus('Success: ${response.statusCode}');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _setStatus('Request canceled');
      } else {
        _setStatus('Error: ${e.message}');
      }
    }
  }

  void _cancelRequest() {
    _cancelTokenService.cancelRequests(this);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _networkInfo.dispose();
    _cancelTokenService.cancelRequests(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('network_kit example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connected: $_connected'),
            const SizedBox(height: 8),
            Text('Status: $_status'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _makeRequest,
              child: const Text('Make GET Request'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _cancelRequest,
              child: const Text('Cancel Request'),
            ),
          ],
        ),
      ),
    );
  }
}

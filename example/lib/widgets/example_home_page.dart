import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart'; 
import 'package:network_kit_example/widgets/connectivity_banner.dart'; 
import 'package:network_kit_example/widgets/loop_requests_page.dart'; 

class ExampleHomePage extends StatefulWidget {
  final CancelTokenService cancelTokenService;

  const ExampleHomePage({super.key, required this.cancelTokenService});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  late final NetworkInfoImplementer _networkInfo;
  StreamSubscription<bool>? _connectivitySub;

  bool _isConnected = true;
  bool _isLoading = false;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _networkInfo = NetworkInfoImplementer(
      Connectivity(),
      events: NetworkEvents(
        onVpnDetected: () async => _setStatus('VPN detected'),
      ),
    );
    _connectivitySub = _networkInfo.onNetworkStatusChanged.listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
    _networkInfo.isConnected.then((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _status = value);
  }

  Future<void> _runSingleRequest({String? factoryName}) async {
    setState(() {
      _isLoading = true;
      _status = 'Calling ${factoryName ?? 'default'} factory...';
    });

    final cancelToken = widget.cancelTokenService.getOrCreateCancelToken(this);

    try {
      final dio = await NetworkKitFactory.dio(factoryName: factoryName);
      final response = await dio.get('posts/1', cancelToken: cancelToken);
      _setStatus(
        '[${factoryName ?? 'default'}] Success HTTP ${response.statusCode}',
      );
    } on DioException catch (e) {
      _setStatus('Dio exception: ${e.message}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openLoopPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                LoopRequestsPage(cancelTokenService: widget.cancelTokenService),
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _networkInfo.dispose();
    widget.cancelTokenService.cancelRequests(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('network_kit example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectivityBanner(isConnected: _isConnected),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Status: $_status'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isLoading ? null : () => _runSingleRequest(),
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Single Request (Default Factory)'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed:
                _isLoading
                    ? null
                    : () => _runSingleRequest(factoryName: 'secondary'),
            icon: const Icon(Icons.storage_outlined),
            label: const Text('Single Request (Named "secondary")'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => widget.cancelTokenService.cancelRequests(this),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel Current Home Request'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openLoopPage,
            icon: const Icon(Icons.repeat),
            label: const Text('Open Loop Requests Page (CancellablePage)'),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/network_events.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
  Stream<bool> get onNetworkStatusChanged;
}

class NetworkInfoImplementer implements NetworkInfo {
  final Connectivity _connectivity;
  final NetworkEvents _events;
  final StreamController<bool> _networkStatusController =
      StreamController<bool>.broadcast();

  NetworkInfoImplementer(
    this._connectivity, {
    NetworkEvents events = const NetworkEvents(),
  }) : _events = events {
    _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> result,
    ) {
      final isConnected = _isConnectedResult(result);
      _networkStatusController.add(isConnected);
    });
  }

  bool _isConnectedResult(List<ConnectivityResult> result) {
    for (final value in result) {
      if (value == ConnectivityResult.vpn) {
        _events.onVpnDetected?.call();
      }
      if (value == ConnectivityResult.wifi ||
          value == ConnectivityResult.mobile) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return _isConnectedResult(result);
  }

  @override
  Stream<bool> get onNetworkStatusChanged => _networkStatusController.stream;

  void dispose() {
    _networkStatusController.close();
  }
}

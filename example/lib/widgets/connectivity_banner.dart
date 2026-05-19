import 'package:flutter/material.dart';

class ConnectivityBanner extends StatelessWidget {
  final bool isConnected;

  const ConnectivityBanner({super.key, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isConnected ? Icons.wifi : Icons.wifi_off, color: color),
          const SizedBox(width: 8),
          Text(
            isConnected ? 'Connected' : 'Offline',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

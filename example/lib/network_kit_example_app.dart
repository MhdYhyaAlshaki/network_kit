import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart';
import 'package:network_kit_example/widgets/example_home_page.dart';

class NetworkKitExampleApp extends StatelessWidget {
  final CancelTokenService cancelTokenService;

  const NetworkKitExampleApp({super.key, required this.cancelTokenService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'network_kit example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: ExampleHomePage(cancelTokenService: cancelTokenService),
    );
  }
}

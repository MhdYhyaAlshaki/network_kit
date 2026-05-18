import 'package:flutter/material.dart';

import '../cancel_token/cancel_token_service.dart';

abstract class CancellablePage extends StatefulWidget {
  final CancelTokenService cancelTokenService;

  const CancellablePage({super.key, required this.cancelTokenService});

  @override
  CancellablePageState createState();
}

abstract class CancellablePageState<P extends CancellablePage>
    extends State<P> {
  Object get cancelContextKey => this;

  @override
  void initState() {
    super.initState();
    widget.cancelTokenService.getOrCreateCancelToken(cancelContextKey);
  }

  @override
  void dispose() {
    widget.cancelTokenService.cancelRequests(cancelContextKey);
    super.dispose();
  }
}

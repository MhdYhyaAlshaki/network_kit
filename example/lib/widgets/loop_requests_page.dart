import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:network_kit/network_kit.dart';

class LoopRequestsPage extends CancellablePage {
  const LoopRequestsPage({super.key, required super.cancelTokenService});

  @override
  CancellablePageState<LoopRequestsPage> createState() =>
      _LoopRequestsPageState();
}

class _LoopRequestsPageState extends CancellablePageState<LoopRequestsPage> {
  final TextEditingController _counterController = TextEditingController(
    text: '5',
  );

  bool _isRunning = false;
  String _selectedFactoryName = 'default';
  final List<String> _logs = <String>[];

  Future<void> _runLoopRequests() async {
    final total = int.tryParse(_counterController.text.trim()) ?? 0;
    if (total <= 0) {
      setState(
        () => _logs.insert(0, 'Please enter a count greater than zero.'),
      );
      return;
    }

    final boundedTotal = total > 50 ? 50 : total;
    //no need to create a cancel token for each loop, CancellablePage will auto-cancel all requests on dispose. If you want to cancel mid-loop, 
    //you can create a cancel token here and check it inside the loop.
    // final cancelToken = widget.cancelTokenService.getOrCreateCancelToken(
    //   cancelContextKey,
    // );

    setState(() {
      _isRunning = true;
      _logs.clear();
      _logs.add('Starting $boundedTotal requests...');
    });

    final dio = await NetworkKitFactory.dio(
      factoryName:
          _selectedFactoryName == 'default' ? null : _selectedFactoryName,
    );

    for (var i = 1; i <= boundedTotal; i++) {
      // if (cancelToken.isCancelled) {
      //   if (mounted) {
      //     setState(() {
      //       _logs.insert(0, 'Cancelled at request #$i');
      //     });
      //   }
      //   break;
      // }

      final postId = ((i - 1) % 10) + 1;

      try {
        final response = await dio.get('posts/$postId');

        if (!mounted) return;
        setState(() {
          _logs.insert(
            0,
            '#$i -> Success HTTP ${response.statusCode} (postId=$postId)',
          );
        });
      } on DioException catch (e) {
        if (!mounted) return;
        setState(() {
          _logs.insert(0, '#$i -> DioException: ${e.message}');
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _logs.insert(0, 'Loop finished.');
    });
  }

  void _cancelLoop() {
    setState(() {
      _logs.insert(0, 'Cancel requested...');
    });
  }

  @override
  void dispose() {
    _counterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loop Requests (CancellablePage)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter number of requests, then run for-loop API calls. '
              'This page extends CancellablePage, so requests are auto-cancelled on dispose.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _counterController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Request count (max 50)',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedFactoryName,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Factory',
              ),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('default')),
                DropdownMenuItem(value: 'secondary', child: Text('secondary')),
              ],
              onChanged:
                  _isRunning
                      ? null
                      : (value) {
                        if (value == null) return;
                        setState(() => _selectedFactoryName = value);
                      },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isRunning ? null : _runLoopRequests,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run Loop Requests'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isRunning ? _cancelLoop : null,
              icon: const Icon(Icons.stop),
              label: const Text('Cancel Running Loop'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(_logs[index]),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

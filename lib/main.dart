import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/services/file_storage_service.dart';
import 'presentation/providers.dart';

/// How long each start-up step may take before it counts as stuck.
const Duration _stepLimit = Duration(seconds: 20);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await start();
}

/// Opens the storage folder and the database, then shows the app. If either
/// fails or hangs, shows what went wrong instead of leaving the launch
/// screen up for ever.
Future<void> start() async {
  String step = 'opening the storage folder';
  try {
    final storage = await FileStorageService.initialise().timeout(_stepLimit);
    step = 'opening the database';
    final database = await AppDatabase.open().timeout(_stepLimit);
    runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          fileStorageProvider.overrideWithValue(storage),
        ],
        child: const ExpenseAssistantApp(),
      ),
    );
  } on Object catch (error, stack) {
    debugPrint('Start-up failed while $step: $error\n$stack');
    runApp(StartupErrorApp(step: step, error: error, stack: stack));
  }
}

/// Shown when the app cannot start: what failed, so it can be reported.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    required this.step,
    required this.error,
    this.stack,
    this.onRetry = start,
    super.key,
  });

  final String step;
  final Object error;
  final StackTrace? stack;
  final Future<void> Function() onRetry;

  String get _report {
    final lines = (stack?.toString() ?? '').split('\n').take(12).join('\n');
    return 'Failed while $step:\n$error\n\n$lines'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Expense Assistant could not start')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Something went wrong while $step. Your receipts are not '
                'deleted. Please send a screenshot of this screen.',
              ),
              const SizedBox(height: 16),
              SelectableText(
                _report,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: _report)),
                      child: const Text('Copy details'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

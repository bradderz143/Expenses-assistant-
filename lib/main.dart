import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/db/app_database.dart';
import 'data/services/file_storage_service.dart';
import 'presentation/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = await FileStorageService.initialise();
  final database = await AppDatabase.open();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        fileStorageProvider.overrideWithValue(storage),
      ],
      child: const ExpenseAssistantApp(),
    ),
  );
}

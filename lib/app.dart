import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'presentation/capture/capture_flow.dart';
import 'presentation/export/export_screen.dart';
import 'presentation/scan/scan_screen.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/trips/trips_screen.dart';

class ExpenseAssistantApp extends StatelessWidget {
  const ExpenseAssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Assistant',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recoverLostCapture());
  }

  /// Android can kill the app while the camera is open. image_picker keeps
  /// the photo; pick it up here so the receipt is not lost.
  Future<void> _recoverLostCapture() async {
    if (!Platform.isAndroid) return;
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty || !mounted) return;
    final files = response.files;
    if (files == null || files.isEmpty) return;
    await CaptureFlow.processPicked(context, ref, files.first.path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ScanScreen(),
          TripsScreen(),
          ExportScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.luggage_outlined),
            selectedIcon: Icon(Icons.luggage),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.ios_share_outlined),
            selectedIcon: Icon(Icons.ios_share),
            label: 'Export',
          ),
        ],
      ),
    );
  }
}

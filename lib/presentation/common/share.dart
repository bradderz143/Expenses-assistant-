import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Hands files to the share sheet: email to your work account, save to
/// OneDrive, etc. The app itself never uploads anything.
Future<void> shareFiles(List<File> files, {String? subject}) async {
  if (files.isEmpty) return;
  await SharePlus.instance.share(ShareParams(
    files: [for (final f in files) XFile(f.path)],
    subject: subject,
  ));
}

const MethodChannel _oneDrive = MethodChannel('expense_assistant/onedrive');

/// Opens the OneDrive app with [file] ready to upload. Returns false when that
/// is not possible here (OneDrive not installed, or not Android), so the
/// caller can fall back to the share sheet.
Future<bool> sendToOneDrive(File file) async {
  if (!Platform.isAndroid) return false;
  try {
    return await _oneDrive.invokeMethod<bool>(
          'sendToOneDrive',
          {'path': file.path},
        ) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Asks where an exported ZIP should go: OneDrive or any other app.
/// Returns false if the user dismissed the choice without sending it.
Future<bool> sendExport(
  BuildContext context,
  File file, {
  String? subject,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Save to OneDrive'),
            subtitle: Text(Platform.isIOS
                ? 'Choose "Save to Files", then OneDrive'
                : 'Opens the OneDrive app to pick a folder'),
            onTap: () => Navigator.pop(context, 'onedrive'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Share or email'),
            onTap: () => Navigator.pop(context, 'share'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null) return false;
  if (choice == 'onedrive' && await sendToOneDrive(file)) return true;
  if (choice == 'onedrive' && Platform.isAndroid && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('OneDrive app not found. Pick it from the share menu.'),
    ));
  }
  await shareFiles([file], subject: subject);
  return true;
}

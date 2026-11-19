import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../common/widgets.dart';
import '../providers.dart';
import '../receipts/receipt_screen.dart';

/// Camera/gallery -> OCR -> draft saved -> review screen.
class CaptureFlow {
  CaptureFlow._();

  static Future<void> start(
    BuildContext context,
    WidgetRef ref, {
    ImageSource source = ImageSource.camera,
  }) async {
    XFile? picked;
    try {
      // No maxWidth/imageQuality: the original must stay untouched.
      picked = await ImagePicker().pickImage(source: source);
    } on PlatformException catch (e) {
      if (context.mounted) {
        showMessage(context, 'Could not open the camera: ${e.message ?? e.code}');
      }
      return;
    }
    if (picked == null || !context.mounted) return;
    await processPicked(context, ref, picked.path);
  }

  static Future<void> processPicked(
    BuildContext context,
    WidgetRef ref,
    String imagePath,
  ) async {
    final outcome = await runWithProgress(
      context,
      message: 'Reading receipt…',
      // image_picker hands back a temporary copy in the app cache.
      task: (_) => ref
          .read(captureReceiptProvider)
          .call(imagePath, deleteSource: true),
    );
    if (!context.mounted) return;
    ref.read(dataRevisionProvider.notifier).bump();
    if (outcome == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReceiptScreen(
        receiptId: outcome.receipt.id,
        readNote: outcome.readNote,
      ),
    ));
  }
}

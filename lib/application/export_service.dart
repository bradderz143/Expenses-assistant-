import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../data/services/file_storage_service.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/expense_package.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/receipt_query.dart';
import '../domain/logic/formatting.dart';
import '../domain/logic/package_naming.dart';
import '../domain/repositories/repositories.dart';

/// What to put in the ZIP.
sealed class ExportScope {
  const ExportScope();
}

/// Every receipt filed under one trip.
class TripScope extends ExportScope {
  const TripScope(this.tripId);
  final String tripId;
}

/// Receipts that are not in any trip.
class UnassignedScope extends ExportScope {
  const UnassignedScope();
}

class ExportException implements Exception {
  const ExportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ExportResult {
  const ExportResult({
    required this.file,
    required this.receiptCount,
    required this.translatedCount,
    this.missingAmountCount = 0,
    this.toCheckCount = 0,
  });

  final File file;
  final int receiptCount;

  /// Receipts that also have a translated sheet in the ZIP.
  final int translatedCount;

  /// Receipts exported without an amount, so their file names say `NoAmount`.
  final int missingAmountCount;

  /// Receipts whose scanned date or amount nobody has checked yet. Their
  /// file names carry those unchecked values.
  final int toCheckCount;
}

/// Builds `<Trip_Name>_<start-date>.zip` in `Expenses/Exports/`:
///
/// ```
/// 2026-11-04_428.50MXN.jpg               original photo
/// 2026-11-04_428.50MXN_translated.pdf    only if you translated it
/// ```
///
/// The UI then hands the ZIP to the share sheet (Save to Files, OneDrive,
/// email to your work account).
class ExportService {
  ExportService({
    required this.receipts,
    required this.trips,
    required this.packages,
    required this.storage,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReceiptRepository receipts;
  final TripRepository trips;
  final PackageRepository packages;
  final FileStorageService storage;
  final DateTime Function() _clock;

  Future<ExportResult> export(ExportScope scope) async {
    final (selected, baseName) = await _resolve(scope);
    if (selected.isEmpty) {
      throw const ExportException('There are no receipts to export.');
    }
    selected.sort((a, b) {
      final byDate = (a.transactionDate ?? a.capturedAt)
          .compareTo(b.transactionDate ?? b.capturedAt);
      return byDate != 0 ? byDate : a.capturedAt.compareTo(b.capturedAt);
    });

    await storage.exportsDir.create(recursive: true);
    final existing = {
      for (final f in await storage.exports()) p.basenameWithoutExtension(f.path),
    };
    final name = PackageNaming.unique(baseName, existing);
    final zipPath = p.join(storage.exportsDir.path, '$name.zip');

    final used = <String>{};
    var exported = 0;
    var translated = 0;
    var missingAmount = 0;
    var toCheck = 0;
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      for (final receipt in selected) {
        final original = File(storage.absolute(receipt.originalImagePath));
        if (!await original.exists()) continue;

        final base = PackageNaming.unique(
          PackageNaming.receiptFileBase(
            date: receipt.transactionDate,
            amountMinor: receipt.amountMinor,
            currency: receipt.currency,
          ),
          used,
        );
        used.add(base);
        await encoder.addFile(original, '$base${_extensionOf(original.path)}');
        exported++;
        if (receipt.amountMinor == null) missingAmount++;
        // A missing amount is already reported; an unchecked date is not.
        if (receipt.checkDate ||
            (receipt.amountMinor != null && receipt.checkAmount)) {
          toCheck++;
        }

        if (receipt.translationStatus == TranslationStatus.complete) {
          final package = await packages.get(receipt.id);
          if (package != null) {
            final pdf = File(storage.absolute(
              p.join(package.packageDir, PackageFiles.translatedPdf),
            ));
            if (await pdf.exists()) {
              await encoder.addFile(pdf, '${base}_translated.pdf');
              translated++;
            }
          }
        }
      }
    } finally {
      await encoder.close();
    }
    if (exported == 0) {
      await File(zipPath).delete();
      throw const ExportException('The receipt photos could not be found.');
    }
    return ExportResult(
      file: File(zipPath),
      receiptCount: exported,
      translatedCount: translated,
      missingAmountCount: missingAmount,
      toCheckCount: toCheck,
    );
  }

  Future<(List<Receipt>, String)> _resolve(ExportScope scope) async {
    switch (scope) {
      case TripScope(:final tripId):
        final trip = await trips.getById(tripId);
        if (trip == null) throw const ExportException('Trip not found.');
        final list = await receipts.search(ReceiptQuery(
          tripId: tripId,
          archive: ArchiveScope.any,
          limit: 100000,
        ));
        return (
          [...list],
          PackageNaming.tripZipName(trip.name, trip.startDate, _clock()),
        );
      case UnassignedScope():
        final list = await receipts.search(const ReceiptQuery(
          archive: ArchiveScope.any,
          limit: 100000,
        ));
        return (
          [
            for (final r in list)
              if (r.tripId == null) r,
          ],
          'Expenses_${Formatting.isoDate(_clock())}',
        );
    }
  }

  static String _extensionOf(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext.isEmpty ? '.jpg' : (ext == '.jpeg' ? '.jpg' : ext);
  }
}

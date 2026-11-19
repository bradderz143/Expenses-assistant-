import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/services/file_storage_service.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/expense_package.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/trip.dart';
import '../domain/logic/claim_documents.dart';
import '../domain/logic/package_naming.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';

/// Keeps each receipt's package folder correct: right place (trip or
/// standalone), right name (date_merchant_amount), and up-to-date generated
/// files. Safe to call repeatedly; every save calls it.
class PackageService {
  PackageService({
    required this.receipts,
    required this.trips,
    required this.translations,
    required this.packages,
    required this.storage,
    required this.pdfRenderer,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReceiptRepository receipts;
  final TripRepository trips;
  final TranslationRepository translations;
  final PackageRepository packages;
  final FileStorageService storage;
  final TranslationDocumentRenderer pdfRenderer;
  final DateTime Function() _clock;

  /// Folder name a receipt *should* have, before de-duplication.
  String desiredFolder(Receipt receipt, Trip? trip) => p.join(
        storage.packageParent(trip),
        PackageNaming.receiptFolder(
          date: receipt.transactionDate,
          merchant: receipt.merchant,
          amountMinor: receipt.amountMinor,
          currency: receipt.currency,
        ),
      );

  /// Picks a free folder path under the same parent as [desired]. Paths in
  /// [ignore] (the receipt's own folder) don't count as taken.
  Future<String> uniqueFolder(
    String desired, {
    Set<String> ignore = const {},
  }) async {
    final taken = (await packages.allPackageDirs())..removeAll(ignore);
    final parent = p.dirname(desired);
    final base = p.basename(desired);
    var candidate = desired;
    var i = 2;
    while (taken.contains(candidate) ||
        (!ignore.contains(candidate) &&
            await storage.existsRelative(candidate))) {
      candidate = p.join(parent, '${base}_$i');
      i++;
    }
    return candidate;
  }

  Future<ExpensePackage> rebuild(String receiptId) async {
    final found = await receipts.getById(receiptId);
    if (found == null) {
      throw StateError('Receipt $receiptId not found');
    }
    var receipt = found;
    final trip =
        receipt.tripId == null ? null : await trips.getById(receipt.tripId!);
    final existing = await packages.get(receiptId);
    // The original always lives in the package folder, so it is the most
    // reliable pointer to where the folder really is (even if a previous
    // rebuild stopped half-way).
    final fromOriginal = p.dirname(receipt.originalImagePath);
    final currentDir = await storage.existsRelative(fromOriginal)
        ? fromOriginal
        : (existing?.packageDir ?? fromOriginal);

    // 1. Location and name.
    final desired = desiredFolder(receipt, trip);
    var targetDir = currentDir;
    if (!_isSameOrSuffixed(currentDir, desired)) {
      targetDir = await uniqueFolder(desired, ignore: {
        currentDir,
        if (existing != null) existing.packageDir,
      });
      await storage.moveDirectory(currentDir, targetDir);
    }
    final originalName = p.basename(receipt.originalImagePath);
    final originalPath = p.join(targetDir, originalName);
    if (originalPath != receipt.originalImagePath) {
      receipt = receipt.copyWith(originalImagePath: originalPath);
      await receipts.upsert(receipt);
    }
    if (existing?.packageDir != targetDir) {
      // Record the move straight away, before anything below can fail.
      await packages.upsert(ExpensePackage(
        receiptId: receiptId,
        packageDir: targetDir,
        hasCrop: existing?.hasCrop ?? false,
        hasTranslation: existing?.hasTranslation ?? false,
        builtAt: existing?.builtAt,
      ));
    }

    // 2. Translation outputs.
    final lines = await translations.linesFor(receiptId);
    final cropRelative = p.join(targetDir, PackageFiles.itemsCrop);
    final cropFile = File(storage.absolute(cropRelative));
    final hasCrop = await cropFile.exists();
    final hasTranslation =
        receipt.translationStatus == TranslationStatus.complete &&
            lines.isNotEmpty;
    final pdfRelative = p.join(targetDir, PackageFiles.translatedPdf);
    final txtRelative = p.join(targetDir, PackageFiles.translatedTxt);
    final now = _clock();

    if (hasTranslation) {
      await storage.writeStringAtomic(
        txtRelative,
        ClaimDocuments.translatedItemsText(receipt: receipt, lines: lines),
      );
      final pdf = await pdfRenderer.render(
        receipt: receipt,
        trip: trip,
        lines: lines,
        generatedAt: now,
        cropImage: hasCrop ? await cropFile.readAsBytes() : null,
      );
      await storage.writeBytesAtomic(pdfRelative, pdf);
    } else {
      await storage.deleteFileIfExists(pdfRelative);
      await storage.deleteFileIfExists(txtRelative);
    }

    // 3. Summary + metadata.
    final attachments = [
      originalName,
      if (hasTranslation) PackageFiles.translatedPdf,
    ];
    await storage.writeStringAtomic(
      p.join(targetDir, PackageFiles.claimSummary),
      ClaimDocuments.claimSummary(
        receipt: receipt,
        trip: trip,
        attachments: attachments,
      ),
    );
    await storage.writeStringAtomic(
      p.join(targetDir, PackageFiles.metadata),
      ClaimDocuments.metadataJson(ClaimDocuments.metadata(
        receipt: receipt,
        trip: trip,
        attachments: attachments,
        generatedAt: now,
        translationLineCount: lines.length,
      )),
    );

    final package = ExpensePackage(
      receiptId: receiptId,
      packageDir: targetDir,
      hasCrop: hasCrop,
      hasTranslation: hasTranslation,
      builtAt: now,
    );
    await packages.upsert(package);
    return package;
  }

  /// True when [current] already is [desired], or [desired] plus a
  /// de-duplication suffix (`_2`, `_3`…), so we don't rename needlessly.
  static bool _isSameOrSuffixed(String current, String desired) {
    if (current == desired) return true;
    if (p.dirname(current) != p.dirname(desired)) return false;
    final pattern = RegExp('^${RegExp.escape(p.basename(desired))}_\\d+\$');
    return pattern.hasMatch(p.basename(current));
  }
}

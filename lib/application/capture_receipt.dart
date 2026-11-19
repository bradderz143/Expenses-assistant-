import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/services/file_storage_service.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/expense_package.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/trip.dart';
import '../domain/logic/formatting.dart';
import '../domain/logic/item_area_detector.dart';
import '../domain/logic/meal_type_guesser.dart';
import '../domain/logic/merchant_memory.dart';
import '../domain/logic/ocr_row_assembler.dart';
import '../domain/logic/receipt_text_parser.dart';
import '../domain/reference/countries.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';
import 'package_service.dart';

/// Which fields OCR read with confidence. The ones it did not are also
/// stored on the receipt ([Receipt.toCheck]) so the review screen and the
/// receipt lists keep showing them until the user has checked.
class CaptureOutcome {
  const CaptureOutcome({
    required this.receipt,
    required this.merchantFound,
    required this.dateFound,
    required this.amountFound,
    this.readNote,
  });

  final Receipt receipt;

  /// Why the text reader produced nothing, when it did not (shown to the user).
  final String? readNote;
  final bool merchantFound;
  final bool dateFound;
  final bool amountFound;
}

/// Step 1 of the 15-second flow: store the original untouched, read it, and
/// save a draft immediately so a receipt is never lost even if the app is
/// closed before the user finishes classifying it.
class CaptureReceiptUseCase {
  CaptureReceiptUseCase({
    required this.receipts,
    required this.trips,
    required this.settings,
    required this.storage,
    required this.ocr,
    required this.translation,
    required this.packages,
    required this.idGenerator,
    this.imageProcessor,
    this.merchantMemory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReceiptRepository receipts;
  final TripRepository trips;
  final SettingsRepository settings;
  final FileStorageService storage;
  final OcrService ocr;
  final TranslationService translation;
  final PackageService packages;
  final String Function() idGenerator;

  /// When set, the photo is straightened and trimmed to the receipt first.
  final ImageProcessor? imageProcessor;

  /// Merchant names the user taught the app by correcting earlier receipts.
  final MerchantMemoryRepository? merchantMemory;
  final DateTime Function() _clock;

  /// [deleteSource]: the picked file is image_picker's temporary copy and
  /// can be removed once it is stored.
  Future<CaptureOutcome> call(
    String pickedImagePath, {
    bool deleteSource = false,
  }) async {
    final now = _clock();
    final today = Formatting.dateOnly(now);
    final prefs = await settings.load();
    final trip = await _activeTrip(prefs.activeTripId, today);

    // Trim to the receipt; on any failure carry on with the photo as taken.
    var workPath = pickedImagePath;
    String? trimmedPath;
    var paperFound = false;
    if (imageProcessor != null) {
      try {
        final out = '${pickedImagePath}_receipt.jpg';
        paperFound = await imageProcessor!.cropToReceipt(pickedImagePath, out);
        workPath = out;
        trimmedPath = out;
      } on Object {
        workPath = pickedImagePath;
      }
    }

    // OCR failure must never lose the photo: carry on with empty fields.
    var ocrResult = OcrResult.empty;
    String? readNote;
    try {
      ocrResult = await ocr.recognise(workPath);
      if (ocrResult.text.trim().isEmpty) {
        readNote = 'The text reader found no text in the photo.';
      }
    } on Object catch (e) {
      ocrResult = OcrResult.empty;
      readNote = 'Text reading failed: $e';
    }
    // White paper on a pale table has no edge to find, so the photo is still
    // as wide as it was taken. The text shows where the receipt is: when it
    // sits in a much wider scene, cut the table (and most fingers) away. The
    // text itself is already read.
    if (trimmedPath != null && !paperFound) {
      final text = ItemAreaDetector.textBlock(ocrResult.lines);
      if (text != null) {
        try {
          await imageProcessor!.trimToText(trimmedPath, text);
        } on Object {
          // Keep the wider photo.
        }
      }
    }
    // With no trip to say where we are, trust what the receipt itself says:
    // place names first, then a currency only one country uses (bolívares
    // mean Venezuela; dollars could be several places, so they decide nothing).
    final textCountry = Countries.detectInText(ocrResult.text);
    var country = trip?.country ?? textCountry ?? prefs.defaultCountry;
    ReceiptTextParser parserFor(String c) => ReceiptTextParser(
          defaultCurrency: Countries.currencyFor(c),
          monthFirstDates: Countries.usesMonthFirstDates(c),
          clock: _clock,
        );
    var parsed = parserFor(country).parse(ocrResult);
    if (trip == null && textCountry == null && parsed.currencyDetected) {
      final byCurrency = Countries.fromCurrency(parsed.currency);
      if (byCurrency != null && byCurrency != country) {
        country = byCurrency;
        parsed = parserFor(country).parse(ocrResult);
      }
    }

    var merchant = parsed.merchant;
    if (merchantMemory != null && ocrResult.text.trim().isNotEmpty) {
      try {
        merchant = MerchantMemory.recall(
              ocrText: ocrResult.text,
              guess: parsed.merchant,
              memory: await merchantMemory!.all(),
            ) ??
            merchant;
      } on Object {
        merchant = parsed.merchant;
      }
    }

    String? language;
    try {
      language = await translation.identifyLanguage(ocrResult.text);
    } on Exception {
      language = null;
    }
    language = Languages.reconcile(
      language ?? Countries.languageFor(country),
      Countries.languageFor(country),
    );
    final needsTranslation = language != null && language != 'en';

    final date = parsed.date ?? today;
    final toCheck = <ScanCheck>[
      if (parsed.date == null)
        ScanCheck.dateNotRead
      else if (parsed.dateDoubtful)
        ScanCheck.dateUnsure,
      if (parsed.amountMinor == null)
        ScanCheck.amountNotRead
      else if (parsed.amountDoubtful)
        ScanCheck.amountUnsure,
    ];
    if (readNote == null && toCheck.length == 2) {
      readNote = 'This photo was hard to read. Check the date and amount, or '
          'retake it closer, flat and in focus.';
    }
    final draft = Receipt(
      id: idGenerator(),
      tripId: trip?.id,
      merchant: merchant,
      transactionDate: date,
      amountMinor: parsed.amountMinor,
      currency: parsed.currency,
      country: country,
      claimType: prefs.defaultClaimType,
      mealType: MealTypeGuesser.fromTimeString(parsed.time) ??
          (date == today ? MealTypeGuesser.fromTime(now.hour, now.minute) : null),
      // The rows as the parser saw them (columns joined by height), so
      // "Show scanned text" shows what the fields were read from.
      rawOcrText: _rowsText(ocrResult),
      detectedLanguage: language,
      translationStatus: needsTranslation
          ? TranslationStatus.pending
          : TranslationStatus.notRequired,
      originalImagePath: '', // set below once the folder exists
      capturedAt: now,
      updatedAt: now,
      toCheck: toCheck,
    );

    final folder = await packages.uniqueFolder(packages.desiredFolder(draft, trip));
    final extension = _extensionOf(workPath);
    final originalRelative =
        p.join(folder, '${PackageFiles.originalStem}$extension');
    await storage.copyIn(workPath, originalRelative);

    final receipt = draft.copyWith(originalImagePath: originalRelative);
    await receipts.upsert(receipt);
    await packages.rebuild(receipt.id);
    if (trimmedPath != null) await _deleteQuietly(trimmedPath);
    if (deleteSource) await _deleteQuietly(pickedImagePath);

    return CaptureOutcome(
      receipt: await receipts.getById(receipt.id) ?? receipt,
      merchantFound: merchant != null,
      dateFound: parsed.date != null && !parsed.dateDoubtful,
      amountFound: parsed.amountMinor != null && !parsed.amountDoubtful,
      readNote: readNote,
    );
  }

  /// The trip set as active in Settings; otherwise a trip whose dates
  /// include today.
  Future<Trip?> _activeTrip(String? activeTripId, DateTime today) async {
    if (activeTripId != null) {
      final trip = await trips.getById(activeTripId);
      if (trip != null) return trip;
    }
    for (final trip in await trips.getAll()) {
      if (trip.contains(today)) return trip;
    }
    return null;
  }

  static String _rowsText(OcrResult ocr) {
    final rows = OcrRowAssembler.assemble(ocr.lines);
    if (rows.isEmpty || ocr.lines.any((l) => !l.hasGeometry)) return ocr.text;
    return rows.map((r) => r.text).join('\n');
  }

  static String _extensionOf(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext.isEmpty ? '.jpg' : (ext == '.jpeg' ? '.jpg' : ext);
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Not important.
    }
  }
}

import 'package:path/path.dart' as p;

import '../data/services/file_storage_service.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/expense_package.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/translation_line.dart';
import '../domain/logic/item_area_detector.dart';
import '../domain/logic/item_classifier.dart';
import '../domain/logic/item_line_parser.dart';
import '../domain/logic/ocr_row_assembler.dart';
import '../domain/logic/receipt_text_lines.dart';
import '../domain/logic/text_normaliser.dart';
import '../domain/reference/claim_taxonomy.dart';
import '../domain/reference/countries.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';
import 'package_service.dart';

/// Lines ready for the user to review before saving.
class TranslationDraft {
  const TranslationDraft({
    required this.sourceLanguage,
    required this.lines,
    this.mode = TranslationMode.items,
    this.warning,
  });

  final String sourceLanguage;
  final List<TranslationLine> lines;

  /// Food and drink items, or the whole receipt's text.
  final TranslationMode mode;

  /// Shown to the user, e.g. when the model could not be downloaded and the
  /// English column needs typing by hand.
  final String? warning;
}

class TranslateItemsUseCase {
  TranslateItemsUseCase({
    required this.receipts,
    required this.translations,
    required this.packages,
    required this.packageService,
    required this.settings,
    required this.storage,
    required this.ocr,
    required this.translator,
    this.imageProcessor,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReceiptRepository receipts;
  final TranslationRepository translations;
  final PackageRepository packages;
  final PackageService packageService;
  final SettingsRepository settings;
  final FileStorageService storage;
  final OcrService ocr;
  final TranslationService translator;

  /// Needed only for [prepareAutomatically].
  final ImageProcessor? imageProcessor;
  final DateTime Function() _clock;

  /// Meals get their food and drink items; anything else (taxi, hotel,
  /// fees) gets the main text of the receipt. Null while no category is set:
  /// then the receipt itself decides (priced items found means items).
  static TranslationMode? modeFor(Receipt receipt) {
    final category = receipt.category;
    if (category == null || category.trim().isEmpty) return null;
    return ClaimTaxonomy.isMealCategory(category)
        ? TranslationMode.items
        : TranslationMode.receiptText;
  }

  /// Finds what to translate on the original photo (the items for a meal,
  /// the main text otherwise), crops to it and pre-translates, with no
  /// drawing by hand. Returns null when nothing usable is found (the caller
  /// then offers the manual crop).
  Future<TranslationDraft?> prepareAutomatically({
    required Receipt receipt,
    void Function(String status)? onProgress,
  }) async {
    final processor = imageProcessor;
    if (processor == null) return null;
    final current = await receipts.getById(receipt.id) ?? receipt;
    final dir = p.dirname(current.originalImagePath);
    final normalisedRel = p.join(dir, '${PackageFiles.draftPrefix}upright.jpg');
    final cropRel = p.join(dir, '${PackageFiles.draftPrefix}auto_crop.jpg');
    try {
      var mode = modeFor(current);
      onProgress?.call(mode == TranslationMode.receiptText
          ? 'Reading the receipt…'
          : 'Finding the items…');
      await processor.normalise(
        storage.absolute(current.originalImagePath),
        storage.absolute(normalisedRel),
      );
      final scan = await ocr.recognise(storage.absolute(normalisedRel));
      var area = mode == TranslationMode.receiptText
          ? null
          : ItemAreaDetector.detect(scan.lines);
      if (area == null && mode == null) mode = TranslationMode.receiptText;
      if (mode == TranslationMode.receiptText) {
        area = ItemAreaDetector.textArea(scan.lines);
      }
      if (area == null) return null;
      await processor.crop(
        storage.absolute(normalisedRel),
        storage.absolute(cropRel),
        left: area.left,
        top: area.top,
        right: area.right,
        bottom: area.bottom,
      );
      // The page was already read whole, in full resolution. Reuse those
      // lines for the cropped area: reading the small crop again gives worse
      // text ("Caraael" for "Caramel").
      final inArea = [
        for (final l in scan.lines)
          if (l.hasGeometry &&
              l.text.trim().isNotEmpty &&
              _within(area, (l.left + l.right) / 2, l.centerY))
            l,
      ];
      return await prepare(
        receipt: current,
        croppedImagePath: storage.absolute(cropRel),
        onProgress: onProgress,
        mode: mode,
        alreadyRead: inArea.isEmpty ? null : OcrResult(text: '', lines: inArea),
      );
    } on Object {
      return null;
    } finally {
      await storage.deleteFileIfExists(normalisedRel);
      await storage.deleteFileIfExists(cropRel);
    }
  }

  static bool _within(ItemArea area, double x, double y) =>
      x >= area.left && x <= area.right && y >= area.top && y <= area.bottom;

  /// Stores the crop as items_crop.jpg, OCRs it, and pre-translates each item
  /// (glossary first, then the on-device model). [mode] null means: the
  /// receipt's category decides, and with no category, whether priced items
  /// are found.
  Future<TranslationDraft> prepare({
    required Receipt receipt,
    required String croppedImagePath,
    void Function(String status)? onProgress,
    TranslationMode? mode,

    /// Text already read from this area (see [prepareAutomatically]); the
    /// crop is then not read again.
    OcrResult? alreadyRead,
  }) async {
    final current = await receipts.getById(receipt.id) ?? receipt;
    final dir = p.dirname(current.originalImagePath);
    // Staged as a draft until save(), so backing out keeps the old crop.
    final cropRelative = p.join(dir, PackageFiles.itemsCropDraft);
    await storage.copyIn(croppedImagePath, cropRelative, overwrite: true);

    onProgress?.call('Reading the text…');
    final result =
        alreadyRead ?? await ocr.recognise(storage.absolute(cropRelative));
    final rows = result.lines.isEmpty
        ? result.text.split('\n')
        : [for (final r in OcrRowAssembler.assemble(result.lines)) r.text];
    var chosen = mode ?? modeFor(current);
    var items = chosen == TranslationMode.receiptText
        ? const <ReceiptItem>[]
        : ItemLineParser.parseSmart(rows);
    if (chosen == null) {
      chosen = items.isEmpty ? TranslationMode.receiptText : TranslationMode.items;
    }
    final wholeText = chosen == TranslationMode.receiptText;
    if (wholeText) {
      items = [
        for (final text in ReceiptTextLines.meaningful(rows))
          ReceiptItem(description: text),
      ];
    }

    final language = await _languageOf(items, receipt);
    final keys = [
      for (final item in items) TextNormaliser.glossaryKey(item.description),
    ];
    final glossary = await translations.glossaryLookup(language, keys.toSet());

    final machine = <int, String>{};
    final copied = <int, String>{};
    String? warning;
    final pending = <int>[
      for (var i = 0; i < items.length; i++)
        if (!glossary.containsKey(keys[i])) i,
    ];

    if (language != 'en') {
      // Menu items already in English (common on receipts from tourist-area
      // restaurants) are kept as printed rather than machine-translated.
      for (final i in [...pending]) {
        final words = items[i].description.trim().split(RegExp(r'\s+'));
        if (words.length < 2) continue;
        String? lineLanguage;
        try {
          lineLanguage = await translator.identifyLanguage(items[i].description);
        } on Exception {
          lineLanguage = null;
        }
        if (lineLanguage == 'en') {
          copied[i] = items[i].description;
          pending.remove(i);
        }
      }
    }

    if (language == 'en') {
      for (final i in pending) {
        copied[i] = items[i].description;
      }
      warning = 'These items look like English. If so, go back and choose '
          '"No translation needed".';
    } else if (pending.isNotEmpty) {
      if (!translator.supports(language)) {
        warning = 'No on-device translation for '
            '${Languages.nameOf(language)}. Please type the English names.';
      } else {
        final ready = await _ensureModels(language, onProgress);
        if (!ready) {
          warning = 'Could not download the ${Languages.nameOf(language)} '
              'translation model (check your connection or the Wi-Fi only '
              'setting). Please type the English names, or try again later.';
        } else {
          onProgress?.call('Translating…');
          try {
            final translated = await translator.translateAll(
              [
                for (final i in pending)
                  ItemWording.expandAbbreviations(items[i].description, language),
              ],
              from: language,
            );
            for (var j = 0; j < pending.length; j++) {
              machine[pending[j]] = translated[j];
            }
          } on Exception {
            warning = 'On-device translation failed. Please type the '
                'English names.';
          }
        }
      }
    }

    if (items.isEmpty) {
      warning = wholeText
          ? 'No text was found in the crop. Try a clearer photo or a wider '
              'crop, or add lines by hand.'
          : 'No item lines were found in the crop. Try cropping more '
              'tightly around the items, or add lines by hand.';
    }

    final lines = <TranslationLine>[
      for (var i = 0; i < items.length; i++)
        TranslationLine(
          lineNo: i + 1,
          quantity: items[i].quantity,
          originalText: items[i].description,
          translatedText: glossary[keys[i]] ?? machine[i] ?? copied[i] ?? '',
          amountText: items[i].amountText,
          sourceLanguage: language,
          category: wholeText
              ? ItemCategory.general
              : ItemClassifier.classify(
                  items[i].description,
                  glossary[keys[i]] ?? machine[i] ?? copied[i] ?? '',
                ),
          engine: glossary.containsKey(keys[i])
              ? TranslationEngine.glossary
              : (machine.containsKey(i)
                  ? TranslationEngine.onDevice
                  : TranslationEngine.manual),
        ),
    ];
    return TranslationDraft(
      sourceLanguage: language,
      lines: lines,
      mode: chosen,
      warning: warning,
    );
  }

  /// Saves reviewed lines, learns manual corrections into the glossary and
  /// regenerates translated_items.pdf/.txt.
  Future<void> save({
    required Receipt receipt,
    required String sourceLanguage,
    required List<TranslationLine> lines,
  }) async {
    // Food first, then drinks, each in receipt order.
    final ordered = [
      for (final category in ItemCategory.values)
        ...lines.where((l) => l.category == category),
    ];
    final cleaned = <TranslationLine>[];
    for (final line in ordered) {
      if (line.originalText.trim().isEmpty &&
          line.translatedText.trim().isEmpty) {
        continue;
      }
      cleaned.add(line.copyWith(lineNo: cleaned.length + 1));
    }
    final current = await receipts.getById(receipt.id) ?? receipt;
    final dir = p.dirname(current.originalImagePath);
    await storage.replaceFile(
      p.join(dir, PackageFiles.itemsCropDraft),
      p.join(dir, PackageFiles.itemsCrop),
    );
    await translations.replaceLines(receipt.id, cleaned);

    for (final line in cleaned) {
      if (line.engine == TranslationEngine.manual &&
          line.originalText.trim().isNotEmpty &&
          line.translatedText.trim().isNotEmpty &&
          sourceLanguage != 'en') {
        await translations.rememberGlossary(
          sourceLanguage,
          TextNormaliser.glossaryKey(line.originalText),
          line.translatedText.trim(),
        );
      }
    }

    await receipts.upsert(current.copyWith(
      translationStatus: cleaned.isEmpty
          ? TranslationStatus.pending
          : TranslationStatus.complete,
      detectedLanguage: sourceLanguage,
      updatedAt: _clock(),
    ));
    await packageService.rebuild(receipt.id);
  }

  /// "This receipt is in English / doesn't need translating."
  Future<void> markNotRequired(Receipt receipt) async {
    final current = await receipts.getById(receipt.id) ?? receipt;
    await receipts.upsert(current.copyWith(
      translationStatus: TranslationStatus.notRequired,
      updatedAt: _clock(),
    ));
    await packageService.rebuild(receipt.id);
  }

  Future<String> _languageOf(List<ReceiptItem> items, Receipt receipt) async {
    final itemText = items.map((i) => i.description).join('. ');
    String? detected;
    try {
      detected = await translator.identifyLanguage(itemText);
    } on Exception {
      detected = null;
    }
    // Short item names ("AGUA MINERAL") are easy to misidentify; trust the
    // full-receipt detection or the country when the item text is weak.
    if (detected == null || (detected == 'en' && itemText.length < 40)) {
      detected = receipt.detectedLanguage;
    }
    // Spanish is often read as Galician, Catalan or Portuguese on short text.
    final expected = Countries.languageFor(receipt.country);
    return Languages.reconcile(detected ?? expected, expected) ?? 'es';
  }

  Future<bool> _ensureModels(
    String language,
    void Function(String status)? onProgress,
  ) async {
    final prefs = await settings.load();
    for (final code in {language, 'en'}) {
      if (await translator.isModelDownloaded(code)) continue;
      onProgress?.call('Downloading ${Languages.nameOf(code)} model (one-off, ~30 MB)…');
      try {
        final ok = await translator.downloadModel(
          code,
          wifiOnly: prefs.wifiOnlyModelDownloads,
        );
        if (!ok) return false;
      } on Exception {
        return false;
      }
    }
    return true;
  }
}

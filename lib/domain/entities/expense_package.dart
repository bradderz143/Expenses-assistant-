/// File names inside every receipt package folder.
class PackageFiles {
  PackageFiles._();

  /// The original keeps the extension it was captured with (normally .jpg).
  static const String originalStem = 'original_receipt';
  static const String itemsCrop = 'items_crop.jpg';

  /// A re-crop waits here until the translation is saved, so backing out
  /// never pairs a new crop with an old translation. Never exported.
  static const String itemsCropDraft = '_draft_items_crop.jpg';
  static const String draftPrefix = '_draft_';
  static const String translatedPdf = 'translated_items.pdf';
  static const String translatedTxt = 'translated_items.txt';
  static const String metadata = 'metadata.json';
  static const String claimSummary = 'claim_summary.txt';
}

/// The generated evidence folder for one receipt.
class ExpensePackage {
  const ExpensePackage({
    required this.receiptId,
    required this.packageDir,
    required this.hasCrop,
    required this.hasTranslation,
    this.builtAt,
  });

  final String receiptId;

  /// Relative to the storage root, e.g.
  /// `Standalone_Expenses/2026-11-04_ElFogon_428.50MXN`.
  final String packageDir;
  final bool hasCrop;
  final bool hasTranslation;
  final DateTime? builtAt;
}

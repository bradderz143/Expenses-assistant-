/// Enumerations shared across the domain. Each enum is persisted by its
/// [Enum.name], so renaming a value requires a database migration.
library;

enum ClaimType {
  expense('Expense Claim', 'Expense'),
  travelPackage('Travel Package Claim', 'Travel Package');

  const ClaimType(this.label, this.shortLabel);

  /// Wording used in the claim summary and metadata.
  final String label;
  final String shortLabel;

  static ClaimType fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return ClaimType.expense;
  }
}

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  refreshments('Refreshments');

  const MealType(this.label);
  final String label;

  static MealType? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Whether the purchased-items translation has been produced.
enum TranslationStatus {
  /// Foreign-language receipt; crop + translation still to do.
  pending,

  /// Receipt is in English (or the user said translation is not needed).
  notRequired,

  /// Translation lines saved and translated_items.pdf generated.
  complete,

  /// Last attempt failed; user can retry or type translations manually.
  failed;

  static TranslationStatus fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return TranslationStatus.pending;
  }
}

/// Something the scan was not sure of. Kept on the receipt until the user
/// has looked at it and saved, so a wrong guess cannot pass unnoticed.
enum ScanCheck {
  /// No date could be read; the day of the scan was filled in instead.
  dateNotRead,

  /// A date was read but may be wrong.
  dateUnsure,

  /// No amount could be read.
  amountNotRead,

  /// An amount was read but may be wrong.
  amountUnsure;

  bool get isDate => this == dateNotRead || this == dateUnsure;
  bool get isAmount => this == amountNotRead || this == amountUnsure;

  /// Stored as comma-separated names; unknown names are ignored.
  static List<ScanCheck> parse(String? stored) {
    if (stored == null || stored.isEmpty) return const [];
    return [
      for (final name in stored.split(','))
        for (final value in values)
          if (value.name == name.trim()) value,
    ];
  }

  static String? store(List<ScanCheck> checks) =>
      checks.isEmpty ? null : checks.map((c) => c.name).join(',');
}

/// Derived workflow status. Stored (denormalised) on each receipt row so the
/// dashboard and filters can query it cheaply.
enum ReceiptStatus {
  needsClassification('Needs details'),
  needsTranslation('Needs translation'),
  ready('Ready for submission'),
  submitted('Submitted');

  const ReceiptStatus(this.label);
  final String label;

  static ReceiptStatus fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return ReceiptStatus.needsClassification;
  }
}

/// Where a translated line came from. Used for audit wording in the PDF and
/// to learn user corrections into the glossary.
enum TranslationEngine {
  onDevice,
  glossary,
  manual;

  static TranslationEngine fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return TranslationEngine.manual;
  }
}

/// Which receipts a query returns: those still in the main view, those
/// archived after export, or both.
enum ArchiveScope { active, archived, any }

/// Purchased items are grouped under these headings in the translation.
/// What the translation step looks for on a receipt.
enum TranslationMode {
  /// Meals: the food and drink lines, grouped.
  items,

  /// Everything else: the meaningful lines of the whole receipt.
  receiptText,
}

enum ItemCategory {
  food('Food'),
  drink('Drinks'),

  /// A line of a non-meal receipt (taxi, hotel…), translated as written.
  general('Receipt text');

  const ItemCategory(this.label);
  final String label;

  static ItemCategory fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return ItemCategory.food;
  }
}

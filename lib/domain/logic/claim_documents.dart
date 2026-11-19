import 'dart:convert';

import '../entities/enums.dart';
import '../entities/receipt.dart';
import '../entities/translation_line.dart';
import '../entities/trip.dart';
import '../reference/countries.dart';
import 'formatting.dart';

/// Builds the text files that go into every package. Pure functions, so the
/// exact output is pinned by unit tests.
class ClaimDocuments {
  ClaimDocuments._();

  static const int metadataSchemaVersion = 1;

  /// claim_summary.txt — laid out to be copied field-by-field into Oracle.
  static String claimSummary({
    required Receipt receipt,
    required List<String> attachments,
    Trip? trip,
  }) {
    final b = StringBuffer()
      ..writeln('CLAIM SUMMARY')
      ..writeln();

    void field(String label, String? value) {
      b
        ..writeln('$label:')
        ..writeln(value == null || value.trim().isEmpty
            ? '(not recorded)'
            : value.trim())
        ..writeln();
    }

    final date = receipt.transactionDate;
    field('Merchant', receipt.merchant);
    field('Date', date == null ? null : Formatting.displayDate(date));
    field('Amount', receipt.amount?.toString());
    field('Claim Type', receipt.claimType.label);
    field('Category', receipt.category);
    if (receipt.isMeal) field('Meal Type', receipt.mealType?.label);
    field('Location', receipt.country);
    if (trip != null) field('Trip', trip.name);
    field('Description', receipt.description);

    b.writeln('Attachments:');
    for (final a in attachments) {
      b.writeln(a);
    }
    return b.toString();
  }

  /// metadata.json — keys follow the brief's schema, plus audit extras.
  static Map<String, Object?> metadata({
    required Receipt receipt,
    required List<String> attachments,
    required DateTime generatedAt,
    Trip? trip,
    int translationLineCount = 0,
  }) {
    final date = receipt.transactionDate;
    return {
      'schemaVersion': metadataSchemaVersion,
      'receiptId': receipt.id,
      'claimType': receipt.claimType.label,
      'category': receipt.category,
      'mealType': receipt.isMeal ? receipt.mealType?.label : null,
      'merchant': receipt.merchant,
      'country': receipt.country,
      'amount': receipt.amount?.amountText,
      'currency': receipt.currency,
      'date': date == null ? null : Formatting.isoDate(date),
      'description': receipt.description,
      'trip': trip == null
          ? null
          : {
              'id': trip.id,
              'name': trip.name,
              'folder': trip.folderName,
            },
      'status': receipt.status.name,
      'translation': {
        'status': receipt.translationStatus.name,
        'sourceLanguage': receipt.detectedLanguage,
        'lineCount': translationLineCount,
      },
      'attachments': attachments,
      'capturedAt': receipt.capturedAt.toUtc().toIso8601String(),
      'submittedAt': receipt.submittedAt?.toUtc().toIso8601String(),
      'generatedAt': generatedAt.toUtc().toIso8601String(),
    };
  }

  static String metadataJson(Map<String, Object?> metadata) =>
      const JsonEncoder.withIndent('  ').convert(metadata);

  /// translated_items.txt
  static String translatedItemsText({
    required Receipt receipt,
    required List<TranslationLine> lines,
  }) {
    final date = receipt.transactionDate;
    final source = Languages.nameOf(
      lines.isNotEmpty ? lines.first.sourceLanguage : receipt.detectedLanguage,
    );
    final wholeReceipt = lines.isNotEmpty &&
        lines.every((l) => l.category == ItemCategory.general);
    final b = StringBuffer()
      ..writeln(wholeReceipt ? 'TRANSLATED RECEIPT' : 'TRANSLATED ITEMS')
      ..writeln()
      ..writeln('Merchant: ${receipt.merchant ?? '(not recorded)'}')
      ..writeln(
          'Date: ${date == null ? '(not recorded)' : Formatting.displayDate(date)}')
      ..writeln('Total: ${receipt.amount?.toString() ?? '(not recorded)'}')
      ..writeln('Translation: $source to English')
      ..writeln();
    for (final category in ItemCategory.values) {
      final group = lines.where((l) => l.category == category).toList();
      if (group.isEmpty) continue;
      if (!wholeReceipt) {
        b
          ..writeln(category.label.toUpperCase())
          ..writeln();
      }
      for (final line in group) {
        b
          ..writeln(line.originalText)
          ..writeln('  = ${line.translatedText}');
      }
      b.writeln();
    }
    b
      ..writeln()
      ..writeln(translationProvenance(lines));
    return b.toString();
  }

  /// One sentence describing how the translation was produced, for auditors.
  static String translationProvenance(List<TranslationLine> lines) {
    final engines = lines.map((l) => l.engine).toSet();
    final parts = <String>[
      if (engines.contains(TranslationEngine.onDevice))
        'on-device machine translation',
      if (engines.contains(TranslationEngine.glossary)) 'saved glossary',
      if (engines.contains(TranslationEngine.manual)) 'manual entry',
    ];
    final how = parts.isEmpty ? 'manual entry' : parts.join(', ');
    return 'Item names translated by $how and reviewed by the claimant.';
  }
}

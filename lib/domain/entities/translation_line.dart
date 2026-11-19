import 'enums.dart';

/// One purchased item, original wording alongside its English translation.
class TranslationLine {
  const TranslationLine({
    required this.lineNo,
    required this.originalText,
    required this.translatedText,
    required this.engine,
    this.quantity,
    this.amountText,
    this.sourceLanguage,
    this.category = ItemCategory.food,
  });

  final int lineNo;
  final String? quantity;
  final String originalText;
  final String translatedText;

  /// As printed on the receipt, e.g. `90.00`. Kept as text: it is evidence,
  /// not a value we calculate with.
  final String? amountText;
  final String? sourceLanguage;
  final TranslationEngine engine;

  /// Heading the item is listed under in the translation.
  final ItemCategory category;

  TranslationLine copyWith({
    int? lineNo,
    String? originalText,
    String? translatedText,
    TranslationEngine? engine,
    ItemCategory? category,
  }) {
    return TranslationLine(
      lineNo: lineNo ?? this.lineNo,
      quantity: quantity,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      amountText: amountText,
      sourceLanguage: sourceLanguage,
      engine: engine ?? this.engine,
      category: category ?? this.category,
    );
  }
}

import '../../domain/entities/enums.dart';
import '../../domain/entities/expense_package.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/translation_line.dart';
import '../../domain/entities/trip.dart';
import '../../domain/logic/formatting.dart';

/// Row <-> entity conversion. Dates are `yyyy-MM-dd`; timestamps are UTC
/// ISO-8601 so ordering by text equals ordering by time.
class Mappers {
  Mappers._();

  static String timestamp(DateTime t) => t.toUtc().toIso8601String();

  static DateTime parseTimestamp(Object? v) => DateTime.parse(v! as String).toLocal();

  static DateTime? parseTimestampOrNull(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  static String? date(DateTime? d) => d == null ? null : Formatting.isoDate(d);

  static DateTime? parseDate(Object? v) => Formatting.parseIsoDate(v as String?);

  // ----------------------------------------------------------------- receipt

  static Map<String, Object?> receiptToRow(Receipt r) => {
        'id': r.id,
        'trip_id': r.tripId,
        'merchant': r.merchant,
        'transaction_date': date(r.transactionDate),
        'amount_minor': r.amountMinor,
        'currency': r.currency,
        'country': r.country,
        'claim_type': r.claimType.name,
        'category': r.category,
        'meal_type': r.mealType?.name,
        'description': r.description,
        'raw_ocr_text': r.rawOcrText,
        'detected_language': r.detectedLanguage,
        'translation_status': r.translationStatus.name,
        'status': r.status.name,
        'original_image_path': r.originalImagePath,
        'captured_at': timestamp(r.capturedAt),
        'updated_at': timestamp(r.updatedAt),
        'submitted_at': r.submittedAt == null ? null : timestamp(r.submittedAt!),
        'archived_at': r.archivedAt == null ? null : timestamp(r.archivedAt!),
        'to_check': ScanCheck.store(r.toCheck),
      };

  static Receipt receiptFromRow(Map<String, Object?> row) => Receipt(
        id: row['id']! as String,
        tripId: row['trip_id'] as String?,
        merchant: row['merchant'] as String?,
        transactionDate: parseDate(row['transaction_date']),
        amountMinor: row['amount_minor'] as int?,
        currency: row['currency']! as String,
        country: row['country']! as String,
        claimType: ClaimType.fromName(row['claim_type'] as String?),
        category: row['category'] as String?,
        mealType: MealType.fromName(row['meal_type'] as String?),
        description: row['description'] as String?,
        rawOcrText: (row['raw_ocr_text'] as String?) ?? '',
        detectedLanguage: row['detected_language'] as String?,
        translationStatus:
            TranslationStatus.fromName(row['translation_status'] as String?),
        originalImagePath: row['original_image_path']! as String,
        capturedAt: parseTimestamp(row['captured_at']),
        updatedAt: parseTimestamp(row['updated_at']),
        submittedAt: parseTimestampOrNull(row['submitted_at']),
        archivedAt: parseTimestampOrNull(row['archived_at']),
        toCheck: ScanCheck.parse(row['to_check'] as String?),
      );

  // -------------------------------------------------------------------- trip

  static Map<String, Object?> tripToRow(Trip t) => {
        'id': t.id,
        'name': t.name,
        'country': t.country,
        'start_date': date(t.startDate),
        'end_date': date(t.endDate),
        'reference_notes': t.referenceNotes,
        'folder_name': t.folderName,
        'is_favourite': t.isFavourite ? 1 : 0,
        'created_at': timestamp(t.createdAt),
        'updated_at': timestamp(t.updatedAt),
      };

  static Trip tripFromRow(Map<String, Object?> row) => Trip(
        id: row['id']! as String,
        name: row['name']! as String,
        country: row['country']! as String,
        startDate: parseDate(row['start_date']),
        endDate: parseDate(row['end_date']),
        referenceNotes: row['reference_notes'] as String?,
        folderName: row['folder_name']! as String,
        isFavourite: (row['is_favourite'] as int?) == 1,
        createdAt: parseTimestamp(row['created_at']),
        updatedAt: parseTimestamp(row['updated_at']),
      );

  // ------------------------------------------------------------- translation

  static Map<String, Object?> lineToRow(String receiptId, TranslationLine l) => {
        'receipt_id': receiptId,
        'line_no': l.lineNo,
        'quantity': l.quantity,
        'original_text': l.originalText,
        'translated_text': l.translatedText,
        'amount_text': l.amountText,
        'source_language': l.sourceLanguage,
        'engine': l.engine.name,
        'category': l.category.name,
      };

  static TranslationLine lineFromRow(Map<String, Object?> row) =>
      TranslationLine(
        lineNo: row['line_no']! as int,
        quantity: row['quantity'] as String?,
        originalText: row['original_text']! as String,
        translatedText: row['translated_text']! as String,
        amountText: row['amount_text'] as String?,
        sourceLanguage: row['source_language'] as String?,
        engine: TranslationEngine.fromName(row['engine'] as String?),
        category: ItemCategory.fromName(row['category'] as String?),
      );

  // ----------------------------------------------------------------- package

  static Map<String, Object?> packageToRow(ExpensePackage p) => {
        'receipt_id': p.receiptId,
        'package_dir': p.packageDir,
        'has_crop': p.hasCrop ? 1 : 0,
        'has_translation': p.hasTranslation ? 1 : 0,
        'built_at': p.builtAt == null ? null : timestamp(p.builtAt!),
      };

  static ExpensePackage packageFromRow(Map<String, Object?> row) =>
      ExpensePackage(
        receiptId: row['receipt_id']! as String,
        packageDir: row['package_dir']! as String,
        hasCrop: (row['has_crop'] as int?) == 1,
        hasTranslation: (row['has_translation'] as int?) == 1,
        builtAt: parseTimestampOrNull(row['built_at']),
      );
}

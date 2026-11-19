import '../reference/claim_taxonomy.dart';
import '../value_objects/money.dart';
import 'enums.dart';

const Object _unset = Object();

/// A captured receipt and everything the user told us about it.
///
/// Immutable: use [copyWith]. Nullable fields can be cleared by passing
/// `null` explicitly, e.g. `copyWith(category: null)`.
class Receipt {
  const Receipt({
    required this.id,
    required this.currency,
    required this.country,
    required this.claimType,
    required this.translationStatus,
    required this.originalImagePath,
    required this.capturedAt,
    required this.updatedAt,
    this.tripId,
    this.merchant,
    this.transactionDate,
    this.amountMinor,
    this.category,
    this.mealType,
    this.description,
    this.rawOcrText = '',
    this.detectedLanguage,
    this.submittedAt,
    this.archivedAt,
    this.toCheck = const [],
  });

  final String id;
  final String? tripId;
  final String? merchant;

  /// Date only (time component is always midnight local).
  final DateTime? transactionDate;
  final int? amountMinor;
  final String currency;
  final String country;
  final ClaimType claimType;
  final String? category;
  final MealType? mealType;
  final String? description;
  final String rawOcrText;

  /// BCP-47 code detected from the receipt text, e.g. `es`.
  final String? detectedLanguage;
  final TranslationStatus translationStatus;

  /// Path relative to the storage root, e.g.
  /// `Trips/Caracas_Workshop_2026/2026-11-04_ElFogon_428.50MXN/original_receipt.jpg`.
  final String originalImagePath;
  final DateTime capturedAt;
  final DateTime updatedAt;

  /// Set when the user marks the claim as submitted in Oracle.
  final DateTime? submittedAt;

  /// Set when the receipt is moved out of the main view (usually after it
  /// has been exported). It is kept, and can be restored.
  final DateTime? archivedAt;

  /// What the scan was not sure of and the user has not yet confirmed.
  final List<ScanCheck> toCheck;

  bool get isArchived => archivedAt != null;

  bool get checkDate => toCheck.any((c) => c.isDate);
  bool get checkAmount => toCheck.any((c) => c.isAmount);

  Money? get amount =>
      amountMinor == null ? null : Money(amountMinor!, currency);

  bool get isMeal => ClaimTaxonomy.isMealCategory(category);

  /// Fields still needed before the claim is complete, in display order.
  List<String> get missingFields => [
        if (merchant == null || merchant!.trim().isEmpty) 'merchant',
        if (transactionDate == null) 'date',
        if (amountMinor == null) 'amount',
        if (!ClaimTaxonomy.isValidCategory(claimType, category)) 'category',
        if (isMeal && mealType == null) 'meal type',
        if (description == null || description!.trim().isEmpty) 'description',
      ];

  bool get isClassified => missingFields.isEmpty;

  ReceiptStatus get status {
    if (submittedAt != null) return ReceiptStatus.submitted;
    if (!isClassified) return ReceiptStatus.needsClassification;
    if (translationStatus == TranslationStatus.pending ||
        translationStatus == TranslationStatus.failed) {
      return ReceiptStatus.needsTranslation;
    }
    return ReceiptStatus.ready;
  }

  Receipt copyWith({
    Object? tripId = _unset,
    Object? merchant = _unset,
    Object? transactionDate = _unset,
    Object? amountMinor = _unset,
    String? currency,
    String? country,
    ClaimType? claimType,
    Object? category = _unset,
    Object? mealType = _unset,
    Object? description = _unset,
    String? rawOcrText,
    Object? detectedLanguage = _unset,
    TranslationStatus? translationStatus,
    String? originalImagePath,
    DateTime? updatedAt,
    Object? submittedAt = _unset,
    Object? archivedAt = _unset,
    List<ScanCheck>? toCheck,
  }) {
    return Receipt(
      id: id,
      tripId: identical(tripId, _unset) ? this.tripId : tripId as String?,
      merchant:
          identical(merchant, _unset) ? this.merchant : merchant as String?,
      transactionDate: identical(transactionDate, _unset)
          ? this.transactionDate
          : transactionDate as DateTime?,
      amountMinor: identical(amountMinor, _unset)
          ? this.amountMinor
          : amountMinor as int?,
      currency: currency ?? this.currency,
      country: country ?? this.country,
      claimType: claimType ?? this.claimType,
      category:
          identical(category, _unset) ? this.category : category as String?,
      mealType:
          identical(mealType, _unset) ? this.mealType : mealType as MealType?,
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      detectedLanguage: identical(detectedLanguage, _unset)
          ? this.detectedLanguage
          : detectedLanguage as String?,
      translationStatus: translationStatus ?? this.translationStatus,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      capturedAt: capturedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedAt: identical(submittedAt, _unset)
          ? this.submittedAt
          : submittedAt as DateTime?,
      archivedAt: identical(archivedAt, _unset)
          ? this.archivedAt
          : archivedAt as DateTime?,
      toCheck: toCheck ?? this.toCheck,
    );
  }
}

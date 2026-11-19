import 'enums.dart';

/// Search criteria for receipts. Value-equal so it can key a Riverpod family.
class ReceiptQuery {
  const ReceiptQuery({
    this.text,
    this.tripId,
    this.category,
    this.status,
    this.from,
    this.to,
    this.archive = ArchiveScope.active,
    this.limit = 200,
  });

  /// Matched against merchant, description, country, category, trip name
  /// and amount.
  final String? text;
  final String? tripId;
  final String? category;
  final ReceiptStatus? status;
  final DateTime? from;
  final DateTime? to;

  /// Archived receipts are hidden from the main view unless asked for.
  final ArchiveScope archive;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is ReceiptQuery &&
      other.text == text &&
      other.tripId == tripId &&
      other.category == category &&
      other.status == status &&
      other.from == from &&
      other.to == to &&
      other.archive == archive &&
      other.limit == limit;

  @override
  int get hashCode =>
      Object.hash(text, tripId, category, status, from, to, archive, limit);
}

class DashboardStats {
  const DashboardStats({
    required this.total,
    required this.needsClassification,
    required this.needsTranslation,
    required this.ready,
    required this.submitted,
  });

  final int total;
  final int needsClassification;
  final int needsTranslation;
  final int ready;
  final int submitted;

  int countFor(ReceiptStatus status) => switch (status) {
        ReceiptStatus.needsClassification => needsClassification,
        ReceiptStatus.needsTranslation => needsTranslation,
        ReceiptStatus.ready => ready,
        ReceiptStatus.submitted => submitted,
      };
}

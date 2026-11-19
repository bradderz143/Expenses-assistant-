const Object _unset = Object();

/// A trip groups receipts, e.g. "Caracas ACS Workshop".
class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.country,
    required this.folderName,
    required this.createdAt,
    required this.updatedAt,
    this.startDate,
    this.endDate,
    this.referenceNotes,
    this.isFavourite = false,
  });

  final String id;
  final String name;
  final String country;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? referenceNotes;

  /// Folder under `Trips/`, fixed when the trip is created so that renaming a
  /// trip never breaks existing package paths.
  final String folderName;
  final bool isFavourite;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool contains(DateTime date) {
    final start = startDate;
    final end = endDate;
    if (start == null && end == null) return false;
    if (start != null && date.isBefore(start)) return false;
    if (end != null && date.isAfter(end)) return false;
    return true;
  }

  Trip copyWith({
    String? name,
    String? country,
    Object? startDate = _unset,
    Object? endDate = _unset,
    Object? referenceNotes = _unset,
    bool? isFavourite,
    DateTime? updatedAt,
  }) {
    return Trip(
      id: id,
      name: name ?? this.name,
      country: country ?? this.country,
      startDate: identical(startDate, _unset)
          ? this.startDate
          : startDate as DateTime?,
      endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
      referenceNotes: identical(referenceNotes, _unset)
          ? this.referenceNotes
          : referenceNotes as String?,
      folderName: folderName,
      isFavourite: isFavourite ?? this.isFavourite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Count and per-currency totals for a trip (amounts in minor units).
class TripSummary {
  const TripSummary({required this.receiptCount, required this.totals});

  final int receiptCount;
  final Map<String, int> totals;

  static const empty = TripSummary(receiptCount: 0, totals: {});
}

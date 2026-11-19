import '../reference/currencies.dart';
import '../value_objects/money.dart';
import 'formatting.dart';
import 'text_normaliser.dart';

/// Folder and file naming rules, e.g. `2026-11-04_ElFogon_428.50MXN`.
class PackageNaming {
  PackageNaming._();

  static String receiptFolder({
    required String currency,
    DateTime? date,
    String? merchant,
    int? amountMinor,
  }) {
    final datePart = date == null ? 'undated' : Formatting.isoDate(date);
    final merchantPart = compactWords(merchant, fallback: 'UnknownMerchant');
    final amountPart = amountMinor == null
        ? 'NoAmount'
        : Money.formatMinor(amountMinor, Currencies.exponentOf(currency));
    return '${datePart}_${merchantPart}_$amountPart$currency';
  }

  /// "El Fogón de la Condesa" -> "ElFogonDeLaCondesa" (max [maxLength]).
  static String compactWords(
    String? text, {
    int maxLength = 30,
    String fallback = 'Unknown',
  }) {
    final words = _words(text);
    if (words.isEmpty) return fallback;
    final joined = words.map(_capitalise).join();
    return joined.length <= maxLength ? joined : joined.substring(0, maxLength);
  }

  /// "Caracas ACS Workshop" + 2026 -> "Caracas_ACS_Workshop_2026".
  static String tripFolder(String name, DateTime? startDate) {
    final words = _words(name).map(_capitalise).toList();
    var base = words.isEmpty ? 'Trip' : words.join('_');
    if (base.length > 48) base = base.substring(0, 48);
    final year = startDate?.year.toString();
    if (year != null && !base.contains(year)) base = '${base}_$year';
    return base;
  }

  /// "Caracas Workshop" starting Nov 2026 -> "Caracas_Workshop_Nov_2026".
  static String tripExportName(String name, DateTime? startDate) {
    final words = _words(name).map(_capitalise).toList();
    var base = words.isEmpty ? 'Trip' : words.join('_');
    if (startDate != null) {
      final suffix = Formatting.monthYear(startDate);
      final year = startDate.year.toString();
      base = base.contains(year)
          ? base.replaceFirst(year, suffix)
          : '${base}_$suffix';
    }
    return base;
  }

  /// File name stem used inside the exported ZIP: `2026-11-04_428.50MXN`.
  /// Translated sheets add `_translated` to the same stem.
  static String receiptFileBase({
    required String currency,
    DateTime? date,
    int? amountMinor,
  }) {
    final datePart = date == null ? 'undated' : Formatting.isoDate(date);
    final amountPart = amountMinor == null
        ? 'NoAmount'
        : Money.formatMinor(amountMinor, Currencies.exponentOf(currency));
    return '${datePart}_$amountPart$currency';
  }

  /// ZIP name from the trip name and its start date:
  /// "Caracas ACS Workshop" + 2026-11-09 -> "Caracas_ACS_Workshop_2026-11-09".
  /// [fallbackDate] is used when the trip has no start date.
  static String tripZipName(
    String name,
    DateTime? startDate,
    DateTime fallbackDate,
  ) {
    final words = _words(name).map(_capitalise).toList();
    var base = words.isEmpty ? 'Trip' : words.join('_');
    if (base.length > 48) base = base.substring(0, 48);
    return '${base}_${Formatting.isoDate(startDate ?? fallbackDate)}';
  }

  /// Appends `_2`, `_3`… until [base] is not in [taken].
  static String unique(String base, Set<String> taken) {
    if (!taken.contains(base)) return base;
    var i = 2;
    while (taken.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }

  static List<String> _words(String? text) {
    if (text == null) return const [];
    // All-caps input ("EL FOGON") is title-cased first; mixed-case input keeps
    // deliberate acronyms ("Caracas ACS Workshop").
    return TextNormaliser.stripDiacritics(TextNormaliser.smartTitleCase(text))
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static String _capitalise(String word) =>
      word[0].toUpperCase() + word.substring(1);
}

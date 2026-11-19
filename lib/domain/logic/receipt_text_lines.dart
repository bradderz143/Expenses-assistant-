import 'text_normaliser.dart';

/// For receipts that are not meals (taxis, hotels, fees…): the lines worth
/// translating, which is everything with words in it, minus reference
/// numbers, web addresses and scanning noise.
class ReceiptTextLines {
  ReceiptTextLines._();

  static final RegExp _web = RegExp(
    r'www\.|https?:|\.(com|mx|net|org|gob|co|ve|sv)\b|@',
    caseSensitive: false,
  );

  static bool isMeaningful(String row) {
    final text = TextNormaliser.collapseSpaces(row);
    final letters = TextNormaliser.letterCount(text);
    if (letters < 3) return false;
    if (_web.hasMatch(text)) return false;
    // Codes and references ("CAS020301462", "220000000000001") are single
    // tokens; real lines ("FECHA 2026-09-18 22:19") have words around them.
    final digits = RegExp(r'\d').allMatches(text).length;
    if (!text.contains(' ') && digits > letters) return false;
    return digits <= letters * 2 + 4;
  }

  /// Meaningful rows in reading order, consecutive duplicates removed,
  /// at most [limit] of them.
  static List<String> meaningful(List<String> rows, {int limit = 40}) {
    final out = <String>[];
    for (final row in rows) {
      final text = TextNormaliser.collapseSpaces(row);
      if (!isMeaningful(text)) continue;
      if (out.isNotEmpty && out.last.toLowerCase() == text.toLowerCase()) {
        continue;
      }
      out.add(text);
      if (out.length >= limit) break;
    }
    return out;
  }
}

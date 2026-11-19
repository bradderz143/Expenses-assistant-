import 'text_normaliser.dart';

/// Something on a receipt that points to a merchant the user has named.
enum ClueKind {
  /// A tax ID or phone number printed on the receipt.
  id,

  /// The wrong name the app guessed before the user corrected it.
  guess,

  /// The corrected name itself, found anywhere in the receipt text.
  printed,
}

class MerchantClue {
  const MerchantClue(this.kind, this.key, this.merchant);

  final ClueKind kind;
  final String key;
  final String merchant;
}

/// Learns merchant names from the user's corrections and recalls them on
/// later receipts from the same place. Pure logic; storage is elsewhere.
class MerchantMemory {
  MerchantMemory._();

  static final RegExp _idRow = RegExp(
    r'\b(tel|tel[eé]fono|phone|nit|nrc|rfc|ruc|cuit|cif|nif|vat\s*(no|reg)|'
    r'registro|r\.?f\.?c)\b',
    caseSensitive: false,
  );

  /// Mexican RFC, e.g. ABC123456XY1.
  static final RegExp _rfc = RegExp(r'\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\b');

  static final RegExp _date = RegExp(r'\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}');

  static final RegExp _digitRun = RegExp(r'\d[\d\s\-./]{5,}\d');

  /// Identifying numbers: tax IDs and phone numbers.
  static Set<String> idsIn(String text) {
    final ids = <String>{};
    for (final row in text.split('\n')) {
      for (final m in _rfc.allMatches(row.toUpperCase())) {
        ids.add(m[0]!);
      }
      if (!_idRow.hasMatch(row)) continue;
      for (final m in _digitRun.allMatches(row)) {
        if (_date.hasMatch(m[0]!)) continue;
        final digits = m[0]!.replaceAll(RegExp(r'\D'), '');
        if (digits.length < 7) continue;
        if (RegExp(r'^(\d)\1+$').hasMatch(digits)) continue; // 00000000
        ids.add(digits);
      }
    }
    return ids;
  }

  static String _key(String s) => TextNormaliser.glossaryKey(s);

  /// What to remember when the user changes [wrongGuess] to [merchant].
  static List<MerchantClue> learn({
    required String ocrText,
    required String merchant,
    String? wrongGuess,
  }) {
    final name = merchant.trim();
    if (name.isEmpty) return const [];
    final clues = <MerchantClue>[
      for (final id in idsIn(ocrText)) MerchantClue(ClueKind.id, id, name),
    ];
    final guess = wrongGuess == null ? '' : _key(wrongGuess);
    if (TextNormaliser.letterCount(guess) >= 4 && guess != _key(name)) {
      clues.add(MerchantClue(ClueKind.guess, guess, name));
    }
    final nameKey = _key(name);
    if (TextNormaliser.letterCount(nameKey) >= 4) {
      clues.add(MerchantClue(ClueKind.printed, nameKey, name));
    }
    return clues;
  }

  /// The remembered merchant for a new receipt, or null.
  static String? recall({
    required String ocrText,
    required String? guess,
    required List<MerchantClue> memory,
  }) {
    if (memory.isEmpty) return null;
    final ids = idsIn(ocrText);
    for (final clue in memory) {
      if (clue.kind == ClueKind.id && ids.contains(clue.key)) {
        return clue.merchant;
      }
    }
    final guessKey = guess == null ? '' : _key(guess);
    if (guessKey.isNotEmpty) {
      for (final clue in memory) {
        if (clue.kind == ClueKind.guess && clue.key == guessKey) {
          return clue.merchant;
        }
      }
    }
    final text = ' ${_key(ocrText)} ';
    MerchantClue? best;
    for (final clue in memory) {
      if (clue.kind != ClueKind.printed) continue;
      if (!text.contains(' ${clue.key} ')) continue;
      if (best == null || clue.key.length > best.key.length) best = clue;
    }
    return best?.merchant;
  }
}

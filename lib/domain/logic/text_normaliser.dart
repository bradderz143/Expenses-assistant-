/// Small text helpers shared by parsing, naming and the glossary.
class TextNormaliser {
  TextNormaliser._();

  static const Map<String, String> _diacritics = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y', 'ß': 'ss',
    'Á': 'A', 'À': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
    'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E',
    'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O', 'Ø': 'O',
    'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U',
    'Ñ': 'N', 'Ç': 'C', 'Ý': 'Y',
  };

  static final RegExp _combiningMarks = RegExp('[̀-ͯ]');

  static String stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacritics[char] ?? char);
    }
    return buffer.toString().replaceAll(_combiningMarks, '');
  }

  /// Key used for glossary lookups: lower-case, no accents, no punctuation,
  /// single spaces. "Café  Americano." -> "cafe americano".
  static String glossaryKey(String input) {
    return stripDiacritics(input)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String collapseSpaces(String input) =>
      input.replaceAll(RegExp(r'\s+'), ' ').trim();

  static int letterCount(String input) =>
      RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]').allMatches(input).length;

  static const Set<String> _lowerWords = {
    'de', 'del', 'la', 'las', 'los', 'el', 'y', 'e', 'en', 'da', 'do', //
    'of', 'the', 'and', 'at', 'on',
  };

  /// "EL FOGON DE LA CONDESA" -> "El Fogon de la Condesa". Mixed-case input
  /// is returned unchanged because it is probably already deliberate.
  static String smartTitleCase(String input) {
    final text = collapseSpaces(input);
    final letters = text.replaceAll(RegExp(r'[^A-Za-zÀ-ÖØ-öø-ÿ]'), '');
    if (letters.isEmpty || letters != letters.toUpperCase()) return text;
    final words = text.toLowerCase().split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (word.isEmpty) continue;
      if (i > 0 && _lowerWords.contains(word)) {
        out.add(word);
      } else {
        out.add(word[0].toUpperCase() + word.substring(1));
      }
    }
    return out.join(' ');
  }
}

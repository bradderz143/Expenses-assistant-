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

  /// Card-terminal reference lines: numbers for the bank, not the claim.
  static final RegExp _reference = RegExp(
    r'^(afiliaci[oó]n|terminal(\s*id)?|autorizaci[oó]n|aut\.|id\s*pbx|'
    r'tr[.,]?\s*no|referencia|n[uú]mero\s*de\s*control|num\.?\s*tarjeta|'
    r'no\.?\s*tarjeta|aid\b|arqc|rrn\b|lote\b|oper\.?\s*\d|folio\s*fiscal|'
    r'serie\b|certificado|rfc\b|r\.f\.c|persona\s+(mor\w*|f[ií]sica)|'
    r'r[eé]g\w{1,2}men\s+(general|fiscal|simplificado))',
    caseSensitive: false,
  );

  /// A masked card number ("534985******4983", "TARJETA: ****4983").
  static final RegExp _cardNumber = RegExp(r'\d{4}\s?\*{2,}|\*{3,}\s?\d{4}');

  /// Lines of an address: kept as printed, since translating street and
  /// district names gives nonsense ("Forests of the Lomas").
  static final RegExp _address = RegExp(
    r'\bc\.?\s?p\.?\s?:?\s?\d{5}\b|,\s*\d{5}\s*$|'
    r'^(paseo|calle|av\.?|avenida|blvd\.?|boulevard|bulevar|calz\.?|calzada|'
    r'carretera|carr\.|col\.?|colonia|prol\.?|prolongaci[oó]n|privada|'
    r'circuito|perif[eé]rico|esq\.?|esquina|rua|travessa)\s|'
    r'\b(ciudad\s+de\s+m[eé]?xico|cdmx|m[eé]xico,?\s*d\.?\s?f\.?)\s*$|'
    r'\b(alc(ald[ií]a)?|del(egaci[oó]n)?|mpio|municipio)\.?\s',
    caseSensitive: false,
  );

  /// A company's legal name ("… S DE RL DE CV", "… SA DE CV").
  static final RegExp _legalName = RegExp(
    r'\bde\s+c\.?\s?v\.?\s*$|\bs\.?\s?a\.?\s?p\.?\s?i\.?\b|'
    r'\bs\.?\s?a\.?\s*$|\bs\.?\s?l\.?\s*$|\bltda\.?\s*$',
    caseSensitive: false,
  );

  /// Indexes of [lines] to keep as printed, not translate: addresses
  /// (including a district line between two address lines) and legal
  /// company names.
  static Set<int> asPrinted(List<String> lines) {
    final address = [for (final l in lines) _address.hasMatch(l)];
    final out = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final between = i > 0 &&
          i + 1 < lines.length &&
          address[i - 1] &&
          address[i + 1] &&
          lines[i].contains(',');
      if (address[i] || between || _legalName.hasMatch(lines[i])) out.add(i);
    }
    return out;
  }

  static bool isMeaningful(String row) {
    final text = TextNormaliser.collapseSpaces(row);
    final letters = TextNormaliser.letterCount(text);
    if (letters < 3) return false;
    if (_web.hasMatch(text)) return false;
    // "XX*** X*****", "=====": rules and stars that OCR half-read as letters.
    final symbols = RegExp(r'[^\sA-Za-z0-9À-ÿ]').allMatches(text).length;
    if (symbols > letters) return false;
    // A label with nothing after it ("BANCO EMISOR:") says nothing.
    if (text.endsWith(':')) return false;
    if (_reference.hasMatch(text)) return false;
    if (_cardNumber.hasMatch(text)) return false;
    // Codes and references ("CAS020301462", "220000000000001") are single
    // tokens; real lines ("FECHA 2026-09-18 22:19") have words around them.
    final digits = RegExp(r'\d').allMatches(text).length;
    if (!text.contains(' ') && digits > letters) return false;
    return digits <= letters * 2 + 4;
  }

  /// A line that is part of running text: long, wordy, no label or price.
  static bool _prose(String text) =>
      text.length >= 20 &&
      !text.contains(':') &&
      !RegExp(r'\d[.,]\d{2}\b').hasMatch(text) &&
      RegExp(r'\d').allMatches(text).length <= 2;

  /// Meaningful rows in reading order, consecutive duplicates removed,
  /// at most [limit] of them. A paragraph the printer wrapped over several
  /// lines ("…INCONDICIONAL-" / "MENTE A PAGAR…") is joined back into one
  /// line, so it is translated as a sentence and not in broken pieces.
  static List<String> meaningful(List<String> rows, {int limit = 40}) {
    final out = <String>[];
    var adjacent = false; // the last kept line was the row just before
    for (final row in rows) {
      final text = TextNormaliser.collapseSpaces(row);
      if (!isMeaningful(text)) {
        adjacent = false;
        continue;
      }
      if (out.isNotEmpty && out.last.toLowerCase() == text.toLowerCase()) {
        continue;
      }
      if (adjacent && _continues(out.last, text)) {
        final previous = out.removeLast();
        out.add(previous.endsWith('-')
            ? previous.substring(0, previous.length - 1) + text
            : '$previous $text');
        continue;
      }
      out.add(text);
      adjacent = true;
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Words that tie one printed line to the next in running text.
  static const Set<String> _endJoiners = {
    'de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'que', 'a', 'al', 'en', //
    'con', 'por', 'para', 'este', 'esta', 'su', 'sus', 'un', 'una', 'of',
    'the', 'and', 'to', 'for', 'with',
  };
  static const Set<String> _startJoiners = {
    'de', 'del', 'y', 'e', 'que', 'a', 'al', 'en', 'of', 'and', 'to',
  };

  /// Whether [next] carries on the sentence [previous] started: a word
  /// broken with a hyphen, or a joining word at the end of one line or the
  /// start of the next ("…DE APERTURA" / "DE CREDITO…").
  static bool _continues(String previous, String next) {
    if (!_prose(next)) return false;
    final tail = previous.endsWith('-')
        ? previous.substring(0, previous.length - 1)
        : previous;
    if (!_prose(tail) && !previous.endsWith('-')) return false;
    if (previous.endsWith('-')) return true;
    final last = previous.split(' ').last.toLowerCase();
    final first = next.split(' ').first.toLowerCase();
    return _endJoiners.contains(last) || _startJoiners.contains(first);
  }
}

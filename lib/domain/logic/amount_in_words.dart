import 'text_normaliser.dart';

/// A total written out in words, as many receipts print under the figures:
/// "(TRES MIL SETECIENTOS SESENTA PESOS 00/100 M.N.)".
class WordsAmount {
  const WordsAmount({
    required this.whole,
    required this.exact,
    required this.formal,
    this.cents,
    this.currency,
  });

  /// The whole-currency part: 3760.
  final int whole;

  /// Hundredths (0 to 99), or null when the receipt does not print them.
  final int? cents;

  /// Every word was read cleanly and the phrase is complete. False when a
  /// damaged word had to be guessed or the start may have been cut off.
  final bool exact;

  /// Written the way a receipt states the amount due ("00/100", "SON:",
  /// "M.N.", "ONLY"), not a passing mention of money in an advert.
  final bool formal;

  /// The currency the words name when only one country uses that word
  /// ("QUETZALES" is GTQ); null for "PESOS", which several do.
  final String? currency;

  /// The amount in minor units; missing hundredths count as zero.
  int toMinor(int exponent) {
    var factor = 1;
    for (var i = 0; i < exponent; i++) {
      factor *= 10;
    }
    final hundredths = cents ?? 0;
    final fraction = switch (exponent) {
      0 => 0,
      1 => hundredths ~/ 10,
      2 => hundredths,
      _ => hundredths * (factor ~/ 100),
    };
    return whole * factor + fraction;
  }

  /// Whether [minor] (an amount in minor units) is this amount. When the
  /// receipt gives no hundredths only the whole part is compared.
  bool matches(int minor, int exponent) {
    if (minor < 0) return false;
    if (cents == null || exponent == 0) {
      var factor = 1;
      for (var i = 0; i < exponent; i++) {
        factor *= 10;
      }
      return minor ~/ factor == whole;
    }
    return minor == toMinor(exponent);
  }

  @override
  String toString() =>
      'WordsAmount($whole${cents == null ? '' : '.${cents.toString().padLeft(2, '0')}'}'
      '${exact ? '' : ', guessed'}${formal ? ', formal' : ''})';
}

enum _Kind { unit, teen, ten, hundred, timesHundred, scale }

class _Word {
  const _Word(this.value, this.kind);
  final int value;
  final _Kind kind;
}

class _Token {
  const _Token(this.text, this.start, this.end, this.row, {this.cents});

  final String text;
  final int start;
  final int end;
  final int row;

  /// Set for an "NN/100" token.
  final int? cents;

  bool get isCents => cents != null;
  bool get isNumeric => !isCents && RegExp(r'^\d+$').hasMatch(text);
}

/// Reads amounts written in words in Spanish, English and Portuguese.
///
/// Deliberately strict: a phrase only counts when it sits next to a currency
/// word or an "NN/100", and every word between its start and that marker is a
/// number word. A phrase with a word it cannot read is dropped rather than
/// half-read, because half of "tres mil setecientos sesenta" is a different,
/// equally valid number.
class AmountInWords {
  AmountInWords._();

  static const Map<String, _Word> _words = {
    // Spanish
    'cero': _Word(0, _Kind.unit),
    'un': _Word(1, _Kind.unit),
    'uno': _Word(1, _Kind.unit),
    'una': _Word(1, _Kind.unit),
    'dos': _Word(2, _Kind.unit),
    'tres': _Word(3, _Kind.unit),
    'cuatro': _Word(4, _Kind.unit),
    'cinco': _Word(5, _Kind.unit),
    'seis': _Word(6, _Kind.unit),
    'siete': _Word(7, _Kind.unit),
    'ocho': _Word(8, _Kind.unit),
    'nueve': _Word(9, _Kind.unit),
    'diez': _Word(10, _Kind.ten), // "diez y seis" on older tills
    'once': _Word(11, _Kind.teen),
    'doce': _Word(12, _Kind.teen),
    'trece': _Word(13, _Kind.teen),
    'catorce': _Word(14, _Kind.teen),
    'quince': _Word(15, _Kind.teen),
    'dieciseis': _Word(16, _Kind.teen),
    'diecisiete': _Word(17, _Kind.teen),
    'dieciocho': _Word(18, _Kind.teen),
    'diecinueve': _Word(19, _Kind.teen),
    'veinte': _Word(20, _Kind.ten),
    'veintiun': _Word(21, _Kind.teen),
    'veintiuno': _Word(21, _Kind.teen),
    'veintiuna': _Word(21, _Kind.teen),
    'veintidos': _Word(22, _Kind.teen),
    'veintitres': _Word(23, _Kind.teen),
    'veinticuatro': _Word(24, _Kind.teen),
    'veinticinco': _Word(25, _Kind.teen),
    'veintiseis': _Word(26, _Kind.teen),
    'veintisiete': _Word(27, _Kind.teen),
    'veintiocho': _Word(28, _Kind.teen),
    'veintinueve': _Word(29, _Kind.teen),
    'treinta': _Word(30, _Kind.ten),
    'cuarenta': _Word(40, _Kind.ten),
    'cincuenta': _Word(50, _Kind.ten),
    'sesenta': _Word(60, _Kind.ten),
    'setenta': _Word(70, _Kind.ten),
    'ochenta': _Word(80, _Kind.ten),
    'noventa': _Word(90, _Kind.ten),
    'cien': _Word(100, _Kind.hundred),
    'ciento': _Word(100, _Kind.hundred),
    'doscientos': _Word(200, _Kind.hundred),
    'doscientas': _Word(200, _Kind.hundred),
    'trescientos': _Word(300, _Kind.hundred),
    'trescientas': _Word(300, _Kind.hundred),
    'cuatrocientos': _Word(400, _Kind.hundred),
    'cuatrocientas': _Word(400, _Kind.hundred),
    'quinientos': _Word(500, _Kind.hundred),
    'quinientas': _Word(500, _Kind.hundred),
    'seiscientos': _Word(600, _Kind.hundred),
    'seiscientas': _Word(600, _Kind.hundred),
    'setecientos': _Word(700, _Kind.hundred),
    'setecientas': _Word(700, _Kind.hundred),
    'ochocientos': _Word(800, _Kind.hundred),
    'ochocientas': _Word(800, _Kind.hundred),
    'novecientos': _Word(900, _Kind.hundred),
    'novecientas': _Word(900, _Kind.hundred),
    'mil': _Word(1000, _Kind.scale),
    'millon': _Word(1000000, _Kind.scale),
    'millones': _Word(1000000, _Kind.scale),
    // English
    'zero': _Word(0, _Kind.unit),
    'one': _Word(1, _Kind.unit),
    'two': _Word(2, _Kind.unit),
    'three': _Word(3, _Kind.unit),
    'four': _Word(4, _Kind.unit),
    'five': _Word(5, _Kind.unit),
    'six': _Word(6, _Kind.unit),
    'seven': _Word(7, _Kind.unit),
    'eight': _Word(8, _Kind.unit),
    'nine': _Word(9, _Kind.unit),
    'ten': _Word(10, _Kind.teen),
    'eleven': _Word(11, _Kind.teen),
    'twelve': _Word(12, _Kind.teen),
    'thirteen': _Word(13, _Kind.teen),
    'fourteen': _Word(14, _Kind.teen),
    'fifteen': _Word(15, _Kind.teen),
    'sixteen': _Word(16, _Kind.teen),
    'seventeen': _Word(17, _Kind.teen),
    'eighteen': _Word(18, _Kind.teen),
    'nineteen': _Word(19, _Kind.teen),
    'twenty': _Word(20, _Kind.ten),
    'thirty': _Word(30, _Kind.ten),
    'forty': _Word(40, _Kind.ten),
    'fourty': _Word(40, _Kind.ten),
    'fifty': _Word(50, _Kind.ten),
    'sixty': _Word(60, _Kind.ten),
    'seventy': _Word(70, _Kind.ten),
    'eighty': _Word(80, _Kind.ten),
    'ninety': _Word(90, _Kind.ten),
    'hundred': _Word(100, _Kind.timesHundred),
    'thousand': _Word(1000, _Kind.scale),
    'lakh': _Word(100000, _Kind.scale),
    'lakhs': _Word(100000, _Kind.scale),
    'lac': _Word(100000, _Kind.scale),
    'lacs': _Word(100000, _Kind.scale),
    'million': _Word(1000000, _Kind.scale),
    'crore': _Word(10000000, _Kind.scale),
    'crores': _Word(10000000, _Kind.scale),
    // Portuguese (words not already above)
    'um': _Word(1, _Kind.unit),
    'uma': _Word(1, _Kind.unit),
    'dois': _Word(2, _Kind.unit),
    'duas': _Word(2, _Kind.unit),
    'quatro': _Word(4, _Kind.unit),
    'sete': _Word(7, _Kind.unit),
    'oito': _Word(8, _Kind.unit),
    'nove': _Word(9, _Kind.unit),
    'dez': _Word(10, _Kind.teen),
    'onze': _Word(11, _Kind.teen),
    'doze': _Word(12, _Kind.teen),
    'treze': _Word(13, _Kind.teen),
    'catorze': _Word(14, _Kind.teen),
    'quatorze': _Word(14, _Kind.teen),
    'quinze': _Word(15, _Kind.teen),
    'dezesseis': _Word(16, _Kind.teen),
    'dezasseis': _Word(16, _Kind.teen),
    'dezessete': _Word(17, _Kind.teen),
    'dezassete': _Word(17, _Kind.teen),
    'dezoito': _Word(18, _Kind.teen),
    'dezenove': _Word(19, _Kind.teen),
    'dezanove': _Word(19, _Kind.teen),
    'vinte': _Word(20, _Kind.ten),
    'trinta': _Word(30, _Kind.ten),
    'quarenta': _Word(40, _Kind.ten),
    'cinquenta': _Word(50, _Kind.ten),
    'sessenta': _Word(60, _Kind.ten),
    'oitenta': _Word(80, _Kind.ten),
    'cem': _Word(100, _Kind.hundred),
    'cento': _Word(100, _Kind.hundred),
    'duzentos': _Word(200, _Kind.hundred),
    'duzentas': _Word(200, _Kind.hundred),
    'trezentos': _Word(300, _Kind.hundred),
    'trezentas': _Word(300, _Kind.hundred),
    'quatrocentos': _Word(400, _Kind.hundred),
    'quatrocentas': _Word(400, _Kind.hundred),
    'quinhentos': _Word(500, _Kind.hundred),
    'quinhentas': _Word(500, _Kind.hundred),
    'seiscentos': _Word(600, _Kind.hundred),
    'seiscentas': _Word(600, _Kind.hundred),
    'setecentos': _Word(700, _Kind.hundred),
    'setecentas': _Word(700, _Kind.hundred),
    'oitocentos': _Word(800, _Kind.hundred),
    'oitocentas': _Word(800, _Kind.hundred),
    'novecentos': _Word(900, _Kind.hundred),
    'novecentas': _Word(900, _Kind.hundred),
    'milhao': _Word(1000000, _Kind.scale),
    'milhoes': _Word(1000000, _Kind.scale),
  };

  /// "treinta Y uno", "three hundred AND sixty", "trinta E um".
  static const Set<String> _joiners = {'y', 'and', 'e'};

  static const Set<String> _currencies = {
    'peso', 'pesos', 'bolivar', 'bolivares', 'dolar', 'dolares', 'sol', //
    'soles', 'quetzal', 'quetzales', 'lempira', 'lempiras', 'colon',
    'colones', 'cordoba', 'cordobas', 'euro', 'euros', 'boliviano',
    'bolivianos', 'guarani', 'guaranies', 'balboa', 'balboas', 'real',
    'reais', 'reales', 'libra', 'libras', 'dollar', 'dollars', 'pound',
    'pounds', 'naira', 'cedi', 'cedis', 'shilling', 'shillings', 'rupee',
    'rupees', 'rand', 'dirham', 'dirhams', 'riyal', 'riyals', 'dinar',
    'dinars', 'franc', 'francs', 'franco', 'francos', 'yen', 'yuan',
    'kwacha', 'birr',
  };

  /// Currency words that belong to one currency. "Peso", "franco" and
  /// "dinar" are shared by several countries and say nothing.
  static const Map<String, String> _currencyCodes = {
    'quetzal': 'GTQ', 'quetzales': 'GTQ', 'lempira': 'HNL', 'lempiras': 'HNL', //
    'bolivar': 'VES', 'bolivares': 'VES', 'colon': 'CRC', 'colones': 'CRC',
    'cordoba': 'NIO', 'cordobas': 'NIO', 'sol': 'PEN', 'soles': 'PEN',
    'boliviano': 'BOB', 'bolivianos': 'BOB', 'guarani': 'PYG',
    'guaranies': 'PYG', 'reais': 'BRL', 'euro': 'EUR', 'euros': 'EUR',
    'dolar': 'USD', 'dolares': 'USD', 'dollar': 'USD', 'dollars': 'USD',
    'pound': 'GBP', 'pounds': 'GBP', 'naira': 'NGN', 'cedi': 'GHS',
    'cedis': 'GHS', 'rupee': 'INR', 'rupees': 'INR', 'rand': 'ZAR',
    'yen': 'JPY', 'birr': 'ETB',
  };

  /// The code for a currency word, allowing one misread letter in a long
  /// word ("QUETZA1ES").
  static String? _codeFor(String text) {
    final exact = _currencyCodes[text];
    if (exact != null) return exact;
    if (text.length < 7 || _currencies.contains(text)) return null;
    String? found;
    for (final entry in _currencyCodes.entries) {
      if (entry.key.length < 7) continue;
      if ((entry.key.length - text.length).abs() > 1) continue;
      if (_distance(text, entry.key, 1) > 1) continue;
      if (found != null && found != entry.value) return null;
      found = entry.value;
    }
    return found;
  }

  /// "con 50 CENTAVOS", "and fifty CENTS".
  static const Set<String> _centWords = {
    'centavo', 'centavos', 'centimo', 'centimos', 'ctvs', 'cts', 'cent', //
    'cents', 'pence', 'paise', 'kobo', 'pesewas',
  };

  /// Between the currency and the cents: "pesos CON 50/100".
  static const Set<String> _centJoiners = {'con', 'y', 'and', 'with', 'e'};

  /// Labels that say "this is the amount in words": "SON:", "IMPORTE CON
  /// LETRA", "Amount in words".
  static const Set<String> _labels = {'son', 'letra', 'letras', 'words', 'say'};

  /// Words that may come straight before the number without being part of it.
  static const Set<String> _fillers = {
    'con', 'en', 'la', 'de', 'por', 'in', 'of', 'the', 'a', 'el', 'los', //
    'pagar', 'recibi', 'recibimos', 'bs', 'mxn', 'usd', 'ves', 'cop', 'sum',
    'suma', 'cantidad', 'importe', 'monto', 'valor', 'total', 'amount',
    // "Q. CIENTO VEINTICINCO CON 50/100", "LPS. DOS MIL…", "US$ TREINTA…"
    'q', 'gtq', 'l', 'lps', 'hnl', 'us', 'crc', 'eur', 'gbp',
  };

  /// After the amount: "M.N.", "M/CTE", "ONLY".
  static const Set<String> _closers = {'mn', 'mcte', 'cte', 'only', 'exactos'};

  /// Works on lower-cased text. The first branch is "00/100", allowing for
  /// zeros read as letters ("OO/1OO") and letters straight after it
  /// ("00/100M.N.").
  static final RegExp _tokenPattern = RegExp(
    r'(?<![a-z0-9])([0-9oq]{1,2})\s?/\s?[1il][0o]{2}(?![0-9])|[a-z0-9]+',
  );

  /// "PESOS00/100": a cents marker glued to the word before it.
  static final RegExp _gluedCents =
      RegExp(r'([a-z])(\d{1,2}\s?/\s?[1il][0o]{2}(?![0-9]))');

  /// Something between two tokens that starts a new phrase: "SON: ", "(**".
  static final RegExp _hardBreak = RegExp(r'[:(*=\[]');

  /// Every amount in words found in [rows], in reading order.
  static List<WordsAmount> find(List<String> rows) {
    final found = <WordsAmount>[];
    for (var i = 0; i < rows.length; i++) {
      // A long amount wraps on to the next row (occasionally two).
      final texts = [
        for (var j = i; j < rows.length && j < i + 3; j++) _normalise(rows[j]),
      ];
      final tokens = <_Token>[];
      for (var j = 0; j < texts.length; j++) {
        tokens.addAll(_tokenise(texts[j], j));
      }
      var index = 0;
      while (index < tokens.length && tokens[index].row == 0) {
        final read = _readAt(tokens, texts, index, rows, i);
        if (read == null) {
          index++;
          continue;
        }
        if (read.$1 != null) found.add(read.$1!);
        index = read.$2;
      }
    }
    return found;
  }

  static String _normalise(String row) => TextNormaliser.stripDiacritics(row)
      .toLowerCase()
      .replaceAllMapped(_gluedCents, (m) => '${m[1]} ${m[2]}');

  static List<_Token> _tokenise(String text, int row) {
    final out = <_Token>[];
    for (final m in _tokenPattern.allMatches(text)) {
      final centDigits = m[1];
      if (centDigits != null) {
        final digits = centDigits.replaceAll(RegExp('[oq]'), '0');
        out.add(_Token(m[0]!, m.start, m.end, row, cents: int.parse(digits)));
      } else {
        out.add(_Token(m[0]!, m.start, m.end, row));
      }
    }
    // "M.N." and "M/CTE" arrive as two pieces.
    for (var i = 0; i + 1 < out.length; i++) {
      if (out[i].text != 'm') continue;
      final next = out[i + 1].text;
      if (next != 'n' && next != 'cte') continue;
      out[i] = _Token('m$next', out[i].start, out[i + 1].end, row);
      out.removeAt(i + 1);
    }
    return out;
  }

  /// The number word [text] stands for. The bool is false when the word was
  /// damaged and had to be matched by likeness.
  static (_Word, bool)? _lookup(String text) {
    final exact = _words[text];
    if (exact != null) return (exact, true);
    if (text.length < 5) return null;
    final limit = text.length >= 9 ? 2 : 1;
    _Word? best;
    var bestDistance = limit + 1;
    var tie = false;
    for (final entry in _words.entries) {
      if ((entry.key.length - text.length).abs() > limit) continue;
      final d = _distance(text, entry.key, limit);
      if (d > limit) continue;
      if (d < bestDistance) {
        best = entry.value;
        bestDistance = d;
        tie = false;
      } else if (d == bestDistance && entry.value.value != best!.value) {
        tie = true;
      }
    }
    // Two different numbers are equally likely: do not guess.
    if (best == null || tie) return null;
    return (best, false);
  }

  static bool _isCurrency(String text) {
    if (_currencies.contains(text)) return true;
    if (text.length < 4 || _words.containsKey(text)) return false;
    for (final c in _currencies) {
      // A four-letter misread only of a longer word: "pess" for "pesos".
      if (text.length == 4 && c.length < 5) continue;
      if ((c.length - text.length).abs() <= 1 && _distance(text, c, 1) <= 1) {
        return true;
      }
    }
    return false;
  }

  /// Edit distance, giving up (returning more than [limit]) early.
  static int _distance(String a, String b, int limit) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      var rowMin = current[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = previous[j - 1] + cost;
        if (previous[j] + 1 < v) v = previous[j] + 1;
        if (current[j - 1] + 1 < v) v = current[j - 1] + 1;
        current[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > limit) return limit + 1;
      previous = current;
    }
    return previous[b.length];
  }

  /// Number words starting at [start]: their values, whether all were read
  /// cleanly, and the index after the last one. Handles a missing space
  /// ("TRESMIL") and a stray one ("SETEC IENTOS").
  static (List<_Word>, bool, int)? _run(List<_Token> tokens, int start) {
    final words = <_Word>[];
    var clean = true;
    var i = start;
    var end = start;
    while (i < tokens.length) {
      final token = tokens[i];
      if (token.isCents) break;
      if (_joiners.contains(token.text)) {
        if (words.isEmpty) break;
        i++;
        continue;
      }
      // A currency word is never a damaged number ("soles" is not "seis").
      if (_currencies.contains(token.text)) break;
      // A word split by a stray space, even when its first half is a number
      // word too: "NOVE NTA" is noventa, "CIEN TO" is ciento.
      if (i + 1 < tokens.length &&
          !tokens[i + 1].isCents &&
          tokens[i + 1].row == token.row &&
          token.text.length > 1) {
        final joined = _words[token.text + tokens[i + 1].text];
        if (joined != null) {
          words.add(joined);
          i += 2;
          end = i;
          continue;
        }
      }
      final exact = _words[token.text];
      if (exact != null) {
        words.add(exact);
        i++;
        end = i;
        continue;
      }
      final split = _split(token.text);
      if (split != null) {
        words.addAll(split);
        i++;
        end = i;
        continue;
      }
      final guess = _lookup(token.text) ?? _lookup(_lettersFor(token.text));
      if (guess == null) break;
      words.add(guess.$1);
      clean = false;
      i++;
      end = i;
    }
    return words.isEmpty ? null : (words, clean, end);
  }

  /// "M1L" -> "mil": digits that stand for the letters they look like.
  static String _lettersFor(String text) {
    if (!RegExp('[a-z]').hasMatch(text)) return text;
    return text
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('5', 's')
        .replaceAll('8', 'b');
  }

  /// "tresmil" -> tres, mil.
  static List<_Word>? _split(String text) {
    if (text.length < 6) return null;
    for (var cut = 2; cut <= text.length - 2; cut++) {
      final a = _words[text.substring(0, cut)];
      final b = _words[text.substring(cut)];
      if (a != null && b != null) return [a, b];
    }
    return null;
  }

  /// The value of a run of number words, or null when they do not form a
  /// number ("dos dos", "mil millones mil").
  static int? _evaluate(List<_Word> words) {
    var total = 0;
    var group = 0;
    // 0 nothing yet, 1 after hundreds, 2 after tens, 3 after units.
    var stage = 0;
    var lastScale = 1 << 62;
    for (final w in words) {
      switch (w.kind) {
        case _Kind.hundred:
          if (stage != 0) return null;
          group += w.value;
          stage = 1;
        case _Kind.ten:
          if (stage > 1) return null;
          group += w.value;
          stage = 2;
        case _Kind.teen:
          if (stage > 1) return null;
          group += w.value;
          stage = 3;
        case _Kind.unit:
          if (stage > 2) return null;
          group += w.value;
          stage = 3;
        case _Kind.timesHundred:
          // "three hundred", "twelve hundred", bare "hundred".
          if (group > 99 || (stage != 0 && stage != 3)) return null;
          group = (group == 0 ? 1 : group) * 100;
          stage = 1;
        case _Kind.scale:
          if (w.value >= lastScale || group > 999) return null;
          total += (group == 0 ? 1 : group) * w.value;
          lastScale = w.value;
          group = 0;
          stage = 0;
      }
    }
    return total + group;
  }

  /// Tries to read an amount whose first number word is `tokens[start]`.
  /// Returns null when no number starts there; otherwise the amount (null if
  /// the phrase had to be rejected) and the index to carry on from.
  static (WordsAmount?, int)? _readAt(
    List<_Token> tokens,
    List<String> texts,
    int start,
    List<String> rows,
    int rowIndex,
  ) {
    final run = _run(tokens, start);
    if (run == null) return null;
    final (words, clean, end) = run;
    final value = _evaluate(words);
    if (value == null) return (null, end);

    // ---- what follows the number
    var i = end;
    var hasCurrency = false;
    // "00/100", "…centavos", "M.N.", "ONLY": how a receipt states an amount.
    var marked = false;
    int? cents;
    bool currencyAt(int k) =>
        k < tokens.length && !tokens[k].isCents && _isCurrency(tokens[k].text);

    // "CIENTO VEINTE Y 50/100 SOLES": the cents come before the currency.
    var j = i;
    if (j < tokens.length && _centJoiners.contains(tokens[j].text)) j++;
    if (j < tokens.length && tokens[j].isCents) {
      cents = tokens[j].cents;
      marked = true;
      i = j + 1;
    }
    var currencyAfter = false;
    String? currencyCode;
    if (currencyAt(i)) {
      hasCurrency = true;
      currencyAfter = true;
      currencyCode = _codeFor(tokens[i].text);
      i++;
    }
    if (cents == null) {
      j = i;
      if (j < tokens.length && _centJoiners.contains(tokens[j].text)) j++;
      if (j < tokens.length && tokens[j].isCents) {
        cents = tokens[j].cents;
        marked = true;
        i = j + 1;
      } else if (j < tokens.length) {
        // "CON CINCUENTA CENTAVOS", "AND 50 CENTS".
        int? spoken;
        var after = j;
        if (tokens[j].isNumeric && tokens[j].text.length <= 2) {
          spoken = int.parse(tokens[j].text);
          after = j + 1;
        } else {
          final centRun = _run(tokens, j);
          if (centRun != null) {
            spoken = _evaluate(centRun.$1);
            after = centRun.$3;
          }
        }
        if (spoken != null &&
            spoken < 100 &&
            after < tokens.length &&
            _centWords.contains(tokens[after].text)) {
          cents = spoken;
          marked = true;
          i = after + 1;
        }
      }
    }
    if (i < tokens.length && _closers.contains(tokens[i].text)) {
      marked = true;
      i++;
    }
    final next = i > end ? i : end;

    // The words stopped at something on the same row that is neither the end
    // of an amount nor a number: "SETENTA Y OCMO PESOS". What was read is
    // only the start of the amount, and a smaller number than the real one.
    if (i == end &&
        end < tokens.length &&
        tokens[end].row == tokens[end - 1].row &&
        !tokens[end].isNumeric) {
      return (null, next);
    }

    // ---- what comes before it
    var labelled = false;
    var uncertainStart = false;
    if (start > 0) {
      final before = tokens[start - 1];
      final sameRow = before.row == tokens[start].row;
      final gap = texts[tokens[start].row]
          .substring(sameRow ? before.end : 0, tokens[start].start);
      final text = before.text;
      if (_isCurrency(text)) {
        hasCurrency = true; // "SON PESOS: UN MIL…", "Rupees Four Hundred"
        currencyCode ??= _codeFor(text);
      } else if (!_labels.contains(text) &&
          !_fillers.contains(text) &&
          !_hardBreak.hasMatch(gap) &&
          !before.isNumeric &&
          !before.isCents) {
        // "…SE7ECIENTOS SESENTA PESOS": the word before cannot be placed,
        // so this may be the tail of a bigger number.
        return (null, next);
      }
      // "IMPORTE CON LETRA: …", "Amount in words: …" a few words back.
      for (var k = start - 1; k >= 0 && k >= start - 4; k--) {
        if (tokens[k].row != tokens[start].row) break;
        if (_labels.contains(tokens[k].text)) labelled = true;
      }
    } else if (rowIndex > 0) {
      // First thing on its row. If the row above ends inside a number, that
      // row's own reading covers (or rejects) this one.
      final above = _tokenise(_normalise(rows[rowIndex - 1]), 0);
      if (above.isNotEmpty) {
        final last = above.last;
        final continues = !last.isCents &&
            !last.isNumeric &&
            (_words.containsKey(last.text) ||
                _joiners.contains(last.text) ||
                _lookup(last.text) != null);
        if (continues) return (null, next);
        if (_labels.contains(last.text)) labelled = true;
        final numberAbove = above.any((t) => _words.containsKey(t.text));
        final placed = last.isNumeric ||
            last.isCents ||
            _labels.contains(last.text) ||
            _fillers.contains(last.text) ||
            _isCurrency(last.text) ||
            _closers.contains(last.text);
        if (numberAbove && !placed) uncertainStart = true;
      }
    }

    // A statement of the amount due ends properly: "00/100", "M.N.", "ONLY",
    // or a label and then the currency after the number. A label alone may
    // be followed by an amount whose end was lost ("CON LETRA: UN MIL" and
    // the next row unreadable), so that only backs up a figure.
    final formal = marked || (labelled && currencyAfter);
    // One number word beside a currency ("GANA MIL PESOS") is not an amount.
    if (!formal && !(hasCurrency && words.length >= 2)) return (null, next);
    return (
      WordsAmount(
        whole: value,
        cents: cents,
        exact: clean && !uncertainStart,
        formal: formal,
        currency: currencyCode,
      ),
      next,
    );
  }
}

import '../reference/countries.dart';
import '../reference/currencies.dart';
import '../services/services.dart';
import '../value_objects/money.dart';
import 'amount_in_words.dart';
import 'ocr_row_assembler.dart';
import 'text_normaliser.dart';

/// Best-effort fields read from a receipt. Anything null was not found and
/// should be highlighted for the user to check.
class ParsedReceipt {
  const ParsedReceipt({
    required this.currency,
    this.merchant,
    this.date,
    this.time,
    this.amountMinor,
    this.currencyDetected = false,
    this.amountDoubtful = false,
    this.dateDoubtful = false,
  });

  final String? merchant;
  final DateTime? date;

  /// The date is a best guess (found only inside a ticket number, or one of
  /// several different dates on the receipt): ask the user to check it.
  final bool dateDoubtful;

  /// 24-hour `HH:mm`, used only to suggest breakfast/lunch/dinner.
  final String? time;
  final int? amountMinor;
  final String currency;
  final bool currencyDetected;

  /// The amount is a best guess: the printed total does not add up (often a
  /// misread digit), or no total could be read and it was worked out from
  /// the rest of the receipt. Ask the user to check it.
  final bool amountDoubtful;
}

/// Extracts merchant, date, total and currency from OCR text.
///
/// Tuned for Latin American and UK receipts (Spanish/English keywords) but
/// written so that adding keywords for other languages is a data change.
class ReceiptTextParser {
  ReceiptTextParser({
    required this.defaultCurrency,
    this.monthFirstDates = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String defaultCurrency;
  final bool monthFirstDates;
  final DateTime Function() _clock;

  ParsedReceipt parse(OcrResult ocr) {
    final rows = OcrRowAssembler.assemble(ocr.lines);
    if (rows.isNotEmpty) {
      return parseRows(
        [for (final r in rows) r.text],
        rowHeights: [for (final r in rows) r.height],
        rowPieces: [
          for (final r in rows)
            [for (final s in r.segments) (s.text, s.height)],
        ],
      );
    }
    return parseRows(ocr.text.split('\n'));
  }

  /// [rowPieces]: the separate OCR lines each row was joined from, with
  /// their heights. A tilted photo can join the shop's name to the line
  /// beside it; the pieces let the name still be found on its own.
  ParsedReceipt parseRows(
    List<String> rawRows, {
    List<double>? rowHeights,
    List<List<(String, double)>>? rowPieces,
  }) {
    final rows = <String>[];
    final heights = <double>[];
    final pieces = <List<(String, double)>>[];
    for (var i = 0; i < rawRows.length; i++) {
      final text = _repairAmounts(
        _joinSplitNumbers(_foldStrayAccents(
          TextNormaliser.collapseSpaces(rawRows[i]),
        )),
      );
      if (text.isEmpty) continue;
      rows.add(text);
      heights.add(
        rowHeights != null && i < rowHeights.length ? rowHeights[i] : 0,
      );
      pieces.add([
        if (rowPieces != null && i < rowPieces.length)
          for (final (t, h) in rowPieces[i])
            if (t.trim().isNotEmpty)
              (_foldStrayAccents(TextNormaliser.collapseSpaces(t)), h),
      ]);
    }
    final (currency, detected) = _detectCurrency(rows);
    final exponent = Currencies.exponentOf(currency);
    final (amount, doubtful) = _checkedTotal(rows, exponent);
    final (date, dateDoubtful) = _date(rows);
    return ParsedReceipt(
      merchant: _merchant(rows, heights, pieces),
      date: date,
      dateDoubtful: dateDoubtful,
      time: _time(rows),
      amountMinor: amount,
      currency: currency,
      currencyDetected: detected,
      amountDoubtful: doubtful,
    );
  }

  /// Accents OCR invents on capitals that Spanish never uses ("SAŃ
  /// ŚALVADOR", "SALẢD"): dropped, so words and place names still match.
  static const Map<String, String> _strayAccents = {
    'ś': 's', 'Ś': 'S', 'ń': 'n', 'Ń': 'N', 'ė': 'e', 'Ė': 'E', 'ẻ': 'e', //
    'Ẻ': 'E', 'ả': 'a', 'Ả': 'A', 'ź': 'z', 'Ź': 'Z', 'ż': 'z', 'Ż': 'Z',
    'ł': 'l', 'Ł': 'L', 'ć': 'c', 'Ć': 'C', 'ě': 'e', 'Ě': 'E', 'ř': 'r',
    'Ř': 'R', 'š': 's', 'Š': 'S', 'č': 'c', 'Č': 'C', 'ž': 'z', 'Ž': 'Z',
    'ů': 'u', 'Ů': 'U', 'ő': 'o', 'Ő': 'O', 'ű': 'u', 'Ű': 'U', 'ā': 'a',
    'Ā': 'A', 'ē': 'e', 'Ē': 'E', 'ī': 'i', 'Ī': 'I', 'ō': 'o', 'Ō': 'O',
    'ū': 'u', 'Ū': 'U', 'ą': 'a', 'Ą': 'A', 'ę': 'e', 'Ę': 'E', 'ǎ': 'a',
    'Ǎ': 'A', 'ẽ': 'e', 'Ẽ': 'E', 'ỳ': 'y', 'Ỳ': 'Y',
  };
  static final RegExp _combining = RegExp('[\u0300-\u036f]');

  static String _foldStrayAccents(String text) {
    if (!text.runes.any((r) => r > 0xFF)) return text;
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_strayAccents[char] ?? char);
    }
    return buffer.toString().replaceAll(_combining, '');
  }

  /// Wide receipt fonts come back as "744 . 599 , 66"; rejoin the number.
  /// A unit price is left alone: "@\$85. 885.00" is two numbers.
  static String _joinSplitNumbers(String row) => row.replaceAllMapped(
        RegExp(r'(\d)\s*([.,])\s+(\d)|(\d)\s+([.,])\s*(\d)'),
        (m) {
          final word = row.lastIndexOf(' ', m.start) + 1;
          if (row.startsWith('@', word)) return m[0]!;
          return m[1] != null
              ? '${m[1]}${m[2]}${m[3]}'
              : '${m[4]}${m[5]}${m[6]}';
        },
      );

  /// A price with letters where digits belong: "$3,76O.OO", "$l,170.00".
  static final RegExp _noisyAmount = RegExp(
    r'(?<![A-Za-z0-9])([$£€]\s?)?'
    r'([0-9OoIl|SBZ]+(?:[.,][0-9OoIl|SBZ]{3})*[.,][0-9OoIl|SBZ]{2})'
    r'(?![A-Za-z0-9])',
  );

  /// Puts back digits that OCR read as look-alike letters, but only inside
  /// something already shaped like a price and mostly made of digits.
  static String _repairAmounts(String row) =>
      row.replaceAllMapped(_noisyAmount, (m) {
        final token = m[2]!;
        if (!RegExp(r'[A-Za-z|]').hasMatch(token)) return m[0]!;
        final digits = RegExp(r'\d').allMatches(token).length;
        final letters = RegExp(r'[A-Za-z|]').allMatches(token).length;
        final startsAsNumber = m[1] != null || RegExp(r'^\d').hasMatch(token);
        if (digits < 2 || digits < letters || !startsAsNumber) return m[0]!;
        final buffer = StringBuffer(m[1] ?? '');
        for (final rune in token.runes) {
          final char = String.fromCharCode(rune);
          buffer.write(_digitLookalikes[char] ?? char);
        }
        return buffer.toString();
      });

  // ---------------------------------------------------------------- merchant

  static final RegExp _merchantNoise = RegExp(
    r'^(de\s+\w|sub\s*-?\s*t|precio|prech?\b|venta\b|inbursa|banorte|bbva|bancomer|'
    r'santander|hsbc|banamex|citibanamex|scotiabank|banregio|afirme|'
    r'azteca|getnet|clip\b|mercado\s*pago|zettle|sumup|netpay|openpay|'
    r'evertec|credomatic|prosa\b|apertura|silla|pers\b|personas|nombre|'
    r'comensales|cubiertos|r\.?\s?f\.?\s?c|rif\b|nit\b|ruc\b|cuit\b|tel\b|tel\.|tel[eé]fono|phone|'
    r'fax|www|http|e-?mail|ticket|factura|nota\b|folio|fecha|date|hora|time\b|'
    r'mesa|table|mesero|waiter|cajero|cashier|bienvenid|welcome|gracias|thank|'
    r'sucursal|branch|calle|av\b|av\.|avenida|blvd|col\b|col\.|colonia|c\.\s?p|'
    r'cp\b|cdmx|ciudad|r[eé]gimen|iva\b|subtotal|total|lugar|expedido|'
    r'domicilio|caja\b|terminal|cliente|orden|order|cuenta|check|'
    r'pre\s*-?\s*[a-z]{1,5}nta|pre\s*-?\s*cheque|pre\s*-?\s*factura|comanda|'
    r'saldo\s*de|cuenta\b|'
    r'consumo|recibo|receipt|copia|original|duplicado|c[oó]digo|codigo|'
    r'forma\s*de\s*pago|nrc\b|giro\b|seniat|corresponsal|'
    r'instituci[oó]n\s*de\s*banca|banca\s*m[uú]ltiple|banca\s*m[oó]vil|'
    r'getnet|transacci|aprobad|aceptad|compra\b|copia\b|zona\s*postal|'
    r'raz[oó]n\s*social|gen[eé]rico|huesped|hu[eé]sped)',
    caseSensitive: false,
  );

  static final RegExp _legalSuffix = RegExp(
    r'[,\s]+(S\.?\s?A\.?(\s?P\.?\s?I\.?)?(\s?DE\s?C\.?\s?V\.?)?|'
    r'S\.?\s?DE\s?R\.?\s?L\.?(\s?DE\s?C\.?\s?V\.?)?|C\.\s?A\.?|LTDA?\.?|'
    r'LIMITED|PLC|INC\.?|LLC|S\.?A\.?S\.?|S\.?\s?C\.?[\s.\-]?S\.?|GMBH)\s*$',
    caseSensitive: false,
  );

  /// Well-known brands, checked before guessing from the layout. App
  /// receipts (Uber, DiDi…) put a greeting in the biggest text, not the name.
  /// Ambiguous words (e.g. "Copa", "United", "Delta") need a qualifier.
  static final List<(RegExp, String)> _brands = [
    (RegExp(r'\buber\s*eats\b', caseSensitive: false), 'Uber Eats'),
    (RegExp(r'\buber\b', caseSensitive: false), 'Uber'),
    (RegExp(r'\bdidi\s*food\b', caseSensitive: false), 'DiDi Food'),
    (RegExp(r'\bdidi\b', caseSensitive: false), 'DiDi'),
    (RegExp(r'\bcabify\b', caseSensitive: false), 'Cabify'),
    (RegExp(r'\brappi\b', caseSensitive: false), 'Rappi'),
    (RegExp(r'\blyft\b', caseSensitive: false), 'Lyft'),
    (RegExp(r'\bairbnb\b', caseSensitive: false), 'Airbnb'),
    (RegExp(r'\bbooking\.com\b', caseSensitive: false), 'Booking.com'),
    (RegExp(r'\bexpedia\b', caseSensitive: false), 'Expedia'),
    (RegExp(r'\baerom[eé]xico\b', caseSensitive: false), 'Aeroméxico'),
    (RegExp(r'\bvolaris\b', caseSensitive: false), 'Volaris'),
    (RegExp(r'\bviva\s*aerobus\b', caseSensitive: false), 'Viva Aerobus'),
    (RegExp(r'\bavianca\b', caseSensitive: false), 'Avianca'),
    (RegExp(r'\bcopa\s*airlines\b', caseSensitive: false), 'Copa Airlines'),
    (RegExp(r'\bbritish\s*airways\b', caseSensitive: false), 'British Airways'),
    (RegExp(r'\biberia\b', caseSensitive: false), 'Iberia'),
    (RegExp(r'\bamerican\s*airlines\b', caseSensitive: false), 'American Airlines'),
    (RegExp(r'\bunited\s*airlines\b', caseSensitive: false), 'United Airlines'),
    (RegExp(r'\bdelta\s*air\s*lines\b', caseSensitive: false), 'Delta Air Lines'),
    (RegExp(r'\bstarbucks\b', caseSensitive: false), 'Starbucks'),
    (RegExp(r'\boxxo\b', caseSensitive: false), 'OXXO'),
    (RegExp(r'\b7[\s-]?eleven\b', caseSensitive: false), '7-Eleven'),
    (RegExp(r'\bwalmart\b', caseSensitive: false), 'Walmart'),
    (RegExp(r'\bcostco\b', caseSensitive: false), 'Costco'),
    (RegExp(r'\bsanborns\b', caseSensitive: false), 'Sanborns'),
    (RegExp(r"\bmcdonald'?s\b", caseSensitive: false), "McDonald's"),
    (RegExp(r'\bburger\s*king\b', caseSensitive: false), 'Burger King'),
    // "KEC": the F of a thermal-printed KFC is often read as an E.
    (RegExp(r'\bk[fe]c\b', caseSensitive: false), 'KFC'),
    (RegExp(r'\bpizza\s*hut\b', caseSensitive: false), 'Pizza Hut'),
    (RegExp(r"\bdomino'?s\s*pizza\b", caseSensitive: false), "Domino's"),
    (RegExp(r'\blittle\s*caesars\b', caseSensitive: false), 'Little Caesars'),
    (RegExp(r"\bcarl'?s\s*jr\b", caseSensitive: false), "Carl's Jr."),
    (RegExp(r'\bmarriott\b', caseSensitive: false), 'Marriott'),
    (RegExp(r'\bhilton\b', caseSensitive: false), 'Hilton'),
    (RegExp(r'\bhyatt\b', caseSensitive: false), 'Hyatt'),
    (RegExp(r'\bholiday\s*inn\b', caseSensitive: false), 'Holiday Inn'),
    (RegExp(r'\bhertz\b', caseSensitive: false), 'Hertz'),
    (RegExp(r'\beuropcar\b', caseSensitive: false), 'Europcar'),
    (RegExp(r'\bpemex\b', caseSensitive: false), 'Pemex'),
    (RegExp(r'\bdufry\b', caseSensitive: false), 'Dufry'),
    (RegExp(r'\byellow\s*cab\b', caseSensitive: false), 'Yellow Cab'),
  ];

  /// App receipts print plan names ("Uber One"); always use the plain name.
  static const Set<String> _appBrands = {
    'Uber', 'Uber Eats', 'DiDi', 'DiDi Food', 'Cabify', 'Rappi', 'Lyft',
    'Airbnb',
  };

  static (RegExp, String)? _knownBrand(List<String> rows) {
    final text = rows.join('\n');
    for (final brand in _brands) {
      if (brand.$1.hasMatch(text)) return brand;
    }
    // A long brand name read with a letter or two wrong ("starbLICks",
    // "stabckS"). Short names are left out: too easy to match by chance.
    final words = [
      for (final m in RegExp('[A-Za-z]{6,}').allMatches(text))
        m[0]!.toLowerCase(),
    ];
    for (final (word, name) in _fuzzyBrands) {
      for (final w in words) {
        if ((w.length - word.length).abs() <= 2 && _editDistance(w, word) <= 2) {
          return (RegExp(RegExp.escape(name), caseSensitive: false), name);
        }
      }
    }
    return null;
  }

  static const List<(String, String)> _fuzzyBrands = [
    ('starbucks', 'Starbucks'),
    ('sanborns', 'Sanborns'),
    ('marriott', 'Marriott'),
    ('europcar', 'Europcar'),
    ('aeromexico', 'Aeroméxico'),
    ('mcdonalds', "McDonald's"),
  ];

  static int _editDistance(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, i);
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = previous[j - 1] + cost;
        if (previous[j] + 1 < v) v = previous[j] + 1;
        if (current[j - 1] + 1 < v) v = current[j - 1] + 1;
        current[j] = v;
      }
      previous = current;
    }
    return previous[b.length];
  }

  /// "Thanks for riding, / Juan": a greeting whose name runs onto the
  /// next line.
  static final RegExp _greeting = RegExp(
    r'^(thanks|thank\s*you|gracias|hola|hi\b|hello|dear|estimad[oa]|'
    r'querid[oa]|we\s*hope|esperamos)',
    caseSensitive: false,
  );

  String? _merchant(
    List<String> rows,
    List<double> heights,
    List<List<(String, double)>> pieces,
  ) {
    final guess = _layoutMerchant(rows, heights, pieces);
    final brand = _knownBrand(rows);
    // Keep a fuller printed name ("Starbucks Coffee") when it is the brand.
    if (brand == null) return guess;
    if (!_appBrands.contains(brand.$2) &&
        guess != null &&
        brand.$1.hasMatch(guess)) {
      return guess;
    }
    return brand.$2;
  }

  /// Drops a leading Mexican RFC ("XXX010101AB1-DUFRY…") and a bank name
  /// printed beside the shop's on a card slip ("Bancamiga EJEMPLO 360").
  static String _cleanCandidate(String row) => row
      .replaceFirst(RegExp(r'^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\s*[-–]?\s*'), '')
      .replaceFirst(
        RegExp(r'^(banc\w*|banco|bank)\s+(?=\S)', caseSensitive: false),
        '',
      );

  String? _layoutMerchant(
    List<String> rows,
    List<double> heights,
    List<List<(String, double)>> pieces,
  ) {
    String? best;
    var bestScore = 0.0;
    String? plain;
    var plainScore = 0.0;
    final limit = rows.length < 8 ? rows.length : 8;
    var maxHeight = 0.0;
    for (var i = 0; i < limit; i++) {
      if (heights[i] > maxHeight) maxHeight = heights[i];
    }
    // Each row, and each piece of a row that OCR joined from several lines.
    final candidates = <(int, String, double)>[
      for (var i = 0; i < limit; i++) ...[
        (i, rows[i], heights[i]),
        if (pieces[i].length > 1)
          for (final (t, h) in pieces[i]) (i, t, h),
      ],
    ];
    for (final (i, text, height) in candidates) {
      final row = _cleanCandidate(text);
      final letters = TextNormaliser.letterCount(row);
      if (letters < 3) continue;
      final digits = RegExp(r'\d').allMatches(row).length;
      if (digits > letters) continue;
      if (_merchantNoise.hasMatch(row) || _greeting.hasMatch(row)) continue;
      // A word that mixes digits and letters ("1OMeAPERTURA", "MYT015") is
      // a code or OCR noise, not a shop name.
      if (row.split(' ').any((w) =>
          w.length >= 4 &&
          RegExp(r'\d').hasMatch(w) &&
          RegExp('[A-Za-z]{2}').hasMatch(w))) {
        continue;
      }
      // Address lines ("CHACAO CARACAS (CHACAO) MIRANDA", "C.EJEMPLO, L.1,
      // COL.CENTRO") name places and streets.
      if (!_legalSuffix.hasMatch(row) &&
          (Countries.detectInText(row) != null ||
              (_addressRow.hasMatch(row) && RegExp(r'[\d,]').hasMatch(row)))) {
        continue;
      }
      if (i > 0 &&
          _greeting.hasMatch(rows[i - 1]) &&
          rows[i - 1].trimRight().endsWith(',')) {
        continue; // the customer's name, not the shop's
      }
      if (_datesIn(row).isNotEmpty) continue;

      var score = 1.0 - i * 0.08;
      // Big print helps a little, but a heading ("PRECUENTA") is often the
      // biggest text; the name is mostly decided by being near the top.
      if (maxHeight > 0) score *= 0.7 + 0.3 * (height / maxHeight);
      final legal = _legalSuffix.hasMatch(row);
      if (legal) score *= 0.9;
      if (row.length > 40) score *= 0.6;
      if (legal) {
        if (score > bestScore) {
          bestScore = score;
          best = row;
        }
      } else if (score > plainScore) {
        plainScore = score;
        plain = row;
      }
    }
    // The registered company ("GRUPO EJEMPLO ALIMENTOS, SA DE CV") is
    // rarely the name on the sign: prefer a plain name from the top lines.
    if (plain != null && plainScore >= bestScore * 0.55) {
      best = plain;
    } else if (plain != null && best == null) {
      best = plain;
    }
    if (best == null) return null;
    // Stylised capitals are sometimes read twice: "HHotel".
    var cleaned = best
        .replaceAllMapped(RegExp(r'\b([A-Z])\1(?=[a-z])'), (m) => m[1]!)
        .replaceAll(_legalSuffix, '');
    cleaned = cleaned.replaceAll(
      RegExp(r'^[^A-Za-z0-9À-ÿ]+|[^A-Za-z0-9À-ÿ)]+$'),
      '',
    );
    cleaned = TextNormaliser.smartTitleCase(cleaned);
    return cleaned.isEmpty ? null : cleaned;
  }

  // -------------------------------------------------------------------- date

  static const Map<String, int> _monthPrefixes = {
    'ene': 1, 'jan': 1, 'feb': 2, 'fev': 2, 'mar': 3, 'abr': 4, 'apr': 4, //
    'may': 5, 'mai': 5, 'jun': 6, 'jul': 7, 'ago': 8, 'aug': 8, 'sep': 9,
    'set': 9, 'oct': 10, 'out': 10, 'nov': 11, 'dic': 12, 'dec': 12,
    'dez': 12,
  };

  static final RegExp _isoDate =
      RegExp(r'(?<!\d)(20\d{2})\s?[-/.]\s?(\d{1,2})\s?[-/.]\s?(\d{1,2})(?!\d)');

  /// Day, month, year in figures. Tolerates the spaces OCR puts round the
  /// separators ("28 / 07 /2026") and a time printed hard against the year
  /// ("28/07/202614:42").
  ///
  /// The same separator twice, so "CAJA 19 - 30/09/2026" is not "19-30-09".
  static final RegExp _numericDate = RegExp(
    r'(?<!\d)(\d{1,2})\s?([-/.])\s?(\d{1,2})\s?\2\s?'
    r'(\d{4}(?=\d{1,2}:\d{2})|\d{4}(?!\d)|\d{2}(?![\d/.\-]))',
  );
  /// "28 JUL 2026", "4 de noviembre de 2026". The year must not be the
  /// start of a time or a price ("26 MAR 14:42", "1 MARUCHAN 18.50").
  static final RegExp _dayMonthName = RegExp(
    r'\b(\d{1,2})[\s\-/.]*(?:de\s+)?([A-Za-zÁÉÍÓÚáéíóú]{3,10})\.?'
    r'[\s\-/.,]*(?:del?\s+)?(\d{4}|\d{2})\b(?![:.,]\d)',
    caseSensitive: false,
  );
  static final RegExp _monthNameDay = RegExp(
    r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})\b(?![:.,]\d)',
    caseSensitive: false,
  );

  /// Streets named after dates ("AV. 5 DE MAYO 12", "20 DE NOVIEMBRE 25").
  static final RegExp _addressRow = RegExp(
    r'\b(av|avda|avenida|calle|colonia|col|blvd|bulevar|boulevard|calz|'
    r'calzada|carretera|carr|esq|esquina|privada|priv|cp|c\.p)\b',
    caseSensitive: false,
  );

  static const List<String> _monthNames = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', //
    'agosto', 'septiembre', 'setiembre', 'octubre', 'noviembre', 'diciembre',
    'january', 'february', 'march', 'april', 'may', 'june', 'july',
    'august', 'september', 'october', 'november', 'december', 'janeiro',
    'fevereiro', 'marco', 'maio', 'junho', 'julho', 'setembro', 'outubro',
    'novembro', 'dezembro',
  ];
  static final RegExp _dateKeyword =
      RegExp(r'fecha|date|emisi[oó]n|emitido', caseSensitive: false);

  /// Dates that are on the receipt but are not the day of purchase: valid
  /// until, tax-authority limits, check-out, date of birth.
  static final RegExp _otherDate = RegExp(
    r'vigencia|vigente|v[aá]lid[oa]|\bvalid\b|vence|vencimiento|caduc|expir|'
    r'l[ií]mite|nacimiento|\bbirth|\bdob\b|resoluci[oó]n|rango\s*autorizado|'
    r'\bhasta\b|\buntil\b|check\s*-?\s*out|\bsalida\b|\bentrega\b|'
    r'best\s*before|use\s*by',
    caseSensitive: false,
  );

  /// A date-shaped run with letters where digits belong: "28/O7/2O26".
  static final RegExp _noisyDate = RegExp(
    r'(?<![A-Za-z0-9])([0-9OoQDIl|SBZ]{1,2})\s?([-/.])\s?'
    r'([0-9OoQDIl|SBZ]{1,2})\s?\2\s?([0-9OoQDIl|SBZ]{4}|[0-9OoQDIl|SBZ]{2})'
    r'(?![A-Za-z0-9])',
  );
  static const Map<String, String> _digitLookalikes = {
    'O': '0', 'o': '0', 'Q': '0', 'D': '0', 'I': '1', 'l': '1', '|': '1', //
    'S': '5', 'B': '8', 'Z': '2',
  };

  /// "Ticket: 20260728-001-100001": the day written as one number inside a
  /// reference. Used only when no ordinary date can be read.
  static final RegExp _compactDate = RegExp(
    r'(?<![\d.,/])(20[1-9]\d)(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?![\d.,/])',
  );
  /// A printed date with its middle unreadable: "28/0'/2026", "28//2026".
  /// Keeps the first number and the year.
  static final RegExp _partialDate = RegExp(
    r"(?<!\d)(\d{1,2})\s?[-/.]\s?[^A-Za-z\s]{0,3}\s?[-/.']\s?(20\d{2})(?!\d)",
  );
  static final RegExp _phoneRow = RegExp(
    r'\b(tel|tels|tel[eé]fono|phone|cel|celular|m[oó]vil|mobile|whats\w*|fax)\b',
    caseSensitive: false,
  );

  /// Puts back digits that OCR read as look-alike letters, but only inside
  /// something already shaped like a date and mostly made of digits.
  /// "16-1 1-2026": a space OCR put inside the month.
  static final RegExp _spaceInDate =
      RegExp(r'(?<=\b\d{1,2}[-/.]\d)\s(?=\d[-/.]\d{2,4}\b)');

  /// "Nov16'26", "NOV 16 '26": month, day and a two-digit year after an
  /// apostrophe, as some tills print it.
  static final RegExp _monthDayShortYear = RegExp(
    r"(?<![A-Za-z])([A-Za-z]{3,9})\.?\s?(\d{1,2})\s?['’`´]\s?(\d{2})(?!\d)",
  );

  static String _repairDates(String row) => row.replaceAllMapped(_noisyDate, (m) {
        final groups = [m[1]!, m[3]!, m[4]!];
        if (groups.any((g) => !RegExp(r'\d').hasMatch(g))) return m[0]!;
        final text = m[0]!;
        if (!RegExp(r'[A-Za-z|]').hasMatch(text)) return text;
        final buffer = StringBuffer();
        for (final rune in text.runes) {
          final char = String.fromCharCode(rune);
          buffer.write(_digitLookalikes[char] ?? char);
        }
        return buffer.toString();
      });

  /// The purchase date and whether it needs checking. A labelled date
  /// ("FECHA 28/07/2026") wins; then a plain one; then a day found inside a
  /// ticket number; last, a date that is labelled as something else.
  (DateTime?, bool) _date(List<String> rows) {
    final now = _clock();
    final latest = DateTime(now.year, now.month, now.day + 1);
    final earliest = DateTime(2010);
    bool inRange(DateTime d) => !d.isBefore(earliest) && !d.isAfter(latest);

    DateTime? labelled;
    final plain = <DateTime>[];
    final other = <DateTime>[];
    final compact = <DateTime>[];
    // (first number, year) of dates whose middle was unreadable.
    final partials = <(int, int)>[];
    for (final raw in rows) {
      final row = _repairDates(raw.replaceAll(_spaceInDate, ''));
      // "FECHA: 12/11/2026  VENCE: 12/12/2026": what comes after the word for
      // another kind of date is that date; what comes before is the
      // purchase.
      final otherWord = _otherDate.firstMatch(row);
      final head = otherWord == null ? row : row.substring(0, otherWord.start);
      final tail = otherWord == null ? '' : row.substring(otherWord.start);
      final dates = _datesIn(head).where(inRange).toList();
      final otherDates = _datesIn(tail).where(inRange).toList();
      other.addAll(otherDates);
      if (dates.isNotEmpty) {
        if (_dateKeyword.hasMatch(head)) {
          labelled ??= dates.first;
        } else {
          plain.addAll(dates);
        }
      }
      if (dates.isNotEmpty || otherDates.isNotEmpty) continue;
      final partial = _partialDate.firstMatch(row);
      if (partial != null) {
        partials.add((int.parse(partial[1]!), int.parse(partial[2]!)));
      }
      if (_phoneRow.hasMatch(row)) continue;
      // "2O26O728": zeros read as the letter O inside a run of digits.
      final digits = row.replaceAll(RegExp(r'(?<=\d)[Oo]|[Oo](?=\d)'), '0');
      for (final m in _compactDate.allMatches(digits)) {
        final found = <DateTime>[];
        _addDate(found, int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        compact.addAll(found.where(inRange));
      }
    }

    final DateTime? date;
    var doubtful = false;
    if (labelled != null) {
      date = labelled;
    } else if (plain.isNotEmpty) {
      date = plain.first;
      // Two different unlabelled dates: the first is only a guess.
      doubtful = plain.any((d) => d != date);
    } else if (compact.isNotEmpty) {
      final found = compact.first;
      date = found;
      // Sure only if what survives of the printed date agrees with it:
      // "28/0'/2026" beside ticket 20260728.
      doubtful = !partials.any((p) =>
          p.$2 == found.year && (p.$1 == found.day || p.$1 == found.month));
    } else if (other.isNotEmpty) {
      date = other.first;
      doubtful = true;
    } else {
      return (null, false);
    }
    final yearAgo = DateTime(now.year - 1, now.month, now.day);
    // An old unlabelled date (often a street name read as one) against a
    // recent day in the ticket number: the ticket number is the better
    // guess.
    if (labelled == null &&
        compact.isNotEmpty &&
        !compact.contains(date) &&
        date.isBefore(yearAgo)) {
      return (compact.first, true);
    }
    // The ticket number disagrees with the printed date: one was misread.
    if (compact.isNotEmpty && !compact.contains(date)) doubtful = true;
    // Receipts are scanned soon after the purchase; an old date is more
    // often a misread year.
    if (date.isBefore(yearAgo)) doubtful = true;
    return (date, doubtful);
  }

  List<DateTime> _datesIn(String row) {
    final found = <DateTime>[];
    for (final m in _isoDate.allMatches(row)) {
      _addDate(found, int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    final numeric = _numericDate.allMatches(row).toList();
    // Beside a full date, "10.05.26" is a time, not a second date.
    final fullYear = found.isNotEmpty || numeric.any((m) => m[4]!.length == 4);
    for (final m in numeric) {
      final shortYear = m[4]!.length == 2;
      if (shortYear && fullYear) continue;
      // "v1.10.26": a version number, not a date. A four-digit year may be
      // glued to a word ("PENA28/07/2026"); a two-digit one may not.
      if (shortYear &&
          m.start > 0 &&
          RegExp('[A-Za-z]').hasMatch(row[m.start - 1])) {
        continue;
      }
      final a = int.parse(m[1]!);
      final b = int.parse(m[3]!);
      final year = _fullYear(int.parse(m[4]!));
      int day;
      int month;
      if (a > 12) {
        day = a;
        month = b;
      } else if (b > 12) {
        day = b;
        month = a;
      } else if (monthFirstDates) {
        month = a;
        day = b;
      } else {
        day = a;
        month = b;
      }
      _addDate(found, year, month, day);
    }
    if (_addressRow.hasMatch(row) && !_dateKeyword.hasMatch(row)) {
      return found;
    }
    for (final m in _dayMonthName.allMatches(row)) {
      final month = _monthFromName(m[2]!);
      if (month == null) continue;
      _addDate(found, _fullYear(int.parse(m[3]!)), month, int.parse(m[1]!));
    }
    for (final m in _monthDayShortYear.allMatches(row)) {
      final month = _monthFromName(m[1]!);
      if (month == null) continue;
      _addDate(found, _fullYear(int.parse(m[3]!)), month, int.parse(m[2]!));
    }
    for (final m in _monthNameDay.allMatches(row)) {
      final month = _monthFromName(m[1]!);
      if (month == null) continue;
      _addDate(found, int.parse(m[3]!), month, int.parse(m[2]!));
    }
    return found;
  }

  static int? _monthFromName(String name) {
    final key = TextNormaliser.stripDiacritics(name).toLowerCase();
    if (key.length < 3) return null;
    if (!_monthNames.any((m) => m.startsWith(key))) return null;
    return _monthPrefixes[key.substring(0, 3)];
  }

  static int _fullYear(int year) => year < 100 ? 2000 + year : year;

  static void _addDate(List<DateTime> out, int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return; // e.g. 31/02
    out.add(date);
  }

  // -------------------------------------------------------------------- time

  static final RegExp _timePattern = RegExp(
    r'\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\s*([ap]\.?\s?m\.?)?',
    caseSensitive: false,
  );
  static final RegExp _timeKeyword =
      RegExp(r'hora|time|fecha|date', caseSensitive: false);

  String? _time(List<String> rows) {
    RegExpMatch? fallback;
    for (final row in rows) {
      final match = _timePattern.firstMatch(row);
      if (match == null) continue;
      if (_timeKeyword.hasMatch(row) || _datesIn(row).isNotEmpty) {
        return _formatTime(match);
      }
      fallback ??= match;
    }
    return fallback == null ? null : _formatTime(fallback);
  }

  static String _formatTime(RegExpMatch m) {
    var hour = int.parse(m[1]!);
    final suffix = m[3]?.toLowerCase();
    if (suffix != null) {
      final pm = suffix.startsWith('p');
      if (pm && hour < 12) hour += 12;
      if (!pm && hour == 12) hour = 0;
    }
    return '${hour.toString().padLeft(2, '0')}:${m[2]}';
  }

  // ------------------------------------------------------------------- total

  static final List<(RegExp, int)> _totalKeywords = [
    (
      RegExp(r'total\s*(con|c/|\+|incl\.?|including)\s*(propina|tip)',
          caseSensitive: false),
      100,
    ),
    (RegExp(r'gran\s*total|grand\s*total', caseSensitive: false), 90),
    (
      RegExp(
        r'total\s*a\s*pagar|importe\s*total|monto\s*total|amount\s*due|'
        r'balance\s*due|total\s*due|total\s*neto',
        caseSensitive: false,
      ),
      80,
    ),
    (RegExp(r'\btotal\b', caseSensitive: false), 60),
    // Taxi and transport tickets: "TARIFA: $440.00", "Trip fare".
    (RegExp(r'\btarifa\b|\bfare\b', caseSensitive: false), 50),
    (
      RegExp(r'\bimporte\b|\bamount\b|\ba\s*pagar\b|\bmonto\b',
          caseSensitive: false),
      40,
    ),
  ];

  /// A total of the goods only ("TOTAL PRODUCTOS $350.00"): used when the
  /// receipt offers nothing better.
  static const int _goodsTotalPriority = 30;

  static final RegExp _notTotal =
      RegExp(r'sub\s*-?\s*t(o)?t(a)?l|%', caseSensitive: false);

  /// A row that counts things instead of pricing them: "Total de productos:
  /// 24", "No. de articulos 3", "ITEMS SOLD 6", "TOTAL PUNTOS 120". Matched
  /// on word stems, with the letters OCR swaps, so "PRODUCTCS" and "ART1CULOS"
  /// are still caught.
  static final RegExp _countLabel = RegExp(
    r'total\s*(?:de\s*|of\s*|number\s*of\s*|no\.?\s*(?:de\s*)?|#\s*)?'
    '$_countedThing|'
    r'(?:\bno\.?|\bn[uú]m\.?|\bnro\.?|#|\bcant\.?|\bcantidad|\bqty\.?|'
    r'\bqtd\.?|\bnumber\s*of)\s*(?:total\s*)?(?:de\s*|of\s*)?'
    '$_countedThing|'
    r'(?:art[ií1l]culos?|[il1|]te[mn]s?|pr[o0]duct[o0]s?|p[il1]e[zs2]as?|'
    r'unidades)\s*(?:vendid|sold|comprad|purchased)',
    caseSensitive: false,
  );
  static const String _countedThing =
      r'(?:art|[il1|]te[mn]|pr[o0]d|p[il1]e[zs2]|pza|pzs|qty|cant|un[il1]d|uds|'
      r'bulto|rengl|partida|l[ií]nea|lines?\b|pers|comensal|pax|cubierto|'
      r'punto|point|kg|kilo|litro|lts?\b|gal[oó]n)';

  /// Signs that money was taken off the bill, which can leave a total below
  /// the price of one item.
  static final RegExp _discountRow = RegExp(
    r'descuento|dscto|\bdesc\b|\bdto\b|discount|promo|cortes[ií]a|bonific|'
    r'rebaja|cup[oó]n|coupon|anticipo|\babono\b|dep[oó]sito|deposit|voucher|'
    r'\bvale\b|ahorro|saving|\b[23]\s?x\s?[12]\b|(?<![\w.,])-[$£€]?\d',
    caseSensitive: false,
  );

  /// A row whose amount is itself the money taken off.
  static final RegExp _moneyOffRow = RegExp(
    r'descuento|dscto|\bdesc\b|\bdto\b|discount|cortes[ií]a|bonific|rebaja|'
    r'cup[oó]n|coupon|anticipo|\babono\b',
    caseSensitive: false,
  );

  static final RegExp _tenderLine = RegExp(
    r'efectivo|cash|cambio|change\b|recibido|tendered|pago\s*con|su\s*pago|'
    r'vuelto',
    caseSensitive: false,
  );

  static final RegExp _idLine = RegExp(
    r'tel|tel[eé]fono|phone|r\.?f\.?c|folio|ticket|autoriz|auth|\baid\b|'
    r'tarjeta|card|cuenta|terminal|afiliaci|referencia|ref\b|#',
    caseSensitive: false,
  );

  /// Reference rows, as whole words so that "PASTEL" is not a phone number.
  static final RegExp _referenceRow = RegExp(
    r'\b(tel|tels|tel[eé]fono|phone|rfc|r\.f\.c|folio|ticket|autorizaci[oó]n|'
    r'aid|terminal|afiliaci[oó]n|referencia|ref|saldo|balance|puntos|points)\b',
    caseSensitive: false,
  );

  static final RegExp _amountToken = RegExp(
    r'(?<![\d.,])-?\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,3})?(?![\d.,])|'
    r'(?<![\d.,])-?\d+[.,]\d{1,3}(?![\d.,])|'
    r'(?<![\d.,])-?\d{1,7}(?![\d.,])',
  );

  /// A row giving the price of one unit, not of what was bought.
  static final RegExp _unitPriceRow = RegExp(
    r'\bprecio\b|\bp\.?\s?u\.?\b|\bc/u\b|/\s?(kg|kilo|lt|lts|l)\b|'
    r'\bpor\s+(kg|kilo|litro|lt)\b|unit\s*price|\bper\s+(kg|lb|litre|liter)\b',
    caseSensitive: false,
  );

  /// "@$59.00": the price of one, printed beside the price of the line.
  static final RegExp _unitPrice =
      RegExp(r'@\s?[$£€]?\s?\d[\d.,]*|\b[xX]\s?[$£€]\s?\d[\d.,]*');

  static int _totalPriority(String row) {
    var best = -1;
    for (final (pattern, priority) in _totalKeywords) {
      if (priority > best && pattern.hasMatch(row)) best = priority;
    }
    return best;
  }

  /// The last amount on a row, preferring one with decimals or thousands
  /// separators.
  _Reading? _lastAmountToken(String original, int exponent) {
    // A time ("12:49") is not money.
    final row = original.replaceAll(_clockTime, ' ');
    RegExpMatch? decimalToken;
    RegExpMatch? integerToken;
    for (final m in _amountToken.allMatches(row)) {
      if (RegExp(r'[.,]\d{1,3}$').hasMatch(m[0]!)) {
        decimalToken = m;
      } else {
        integerToken = m;
      }
    }
    final token = decimalToken ?? integerToken;
    if (token == null) return null;
    final value = Money.parseMinor(token[0]!, exponent: exponent);
    if (value == null) return null;
    return _Reading(
      value,
      bare: decimalToken == null,
      signless: decimalToken == null ? null : _signless(row, token, exponent),
    );
  }

  int? _lastAmount(String row, int exponent) =>
      _lastAmountToken(row, exponent)?.amount;

  static final RegExp _clockTime = RegExp(r'(?<!\d)\d{1,2}:\d{2}(?::\d{2})?(?!\d)');

  /// "$" is sometimes read as 5 or 8, giving "53,760.00" for "$3,760.00".
  /// For an amount that starts with one of those and has no currency sign of
  /// its own, this is the reading without that first digit. Only ever used
  /// when something else on the receipt backs it.
  static int? _signless(String row, RegExpMatch token, int exponent) {
    final text = token[0]!;
    if (!RegExp(r'^[58][1-9]').hasMatch(text)) return null;
    if (RegExp(r'[$£€]\s?$').hasMatch(row.substring(0, token.start))) {
      return null;
    }
    return Money.parseMinor(text.substring(1), exponent: exponent);
  }

  /// A tip or service charge on its own (not a total that includes it).
  static final RegExp _tipOnly = RegExp(
    r'propina|\btip\b|gratuity|servicio|service\s*charge',
    caseSensitive: false,
  );
  static final RegExp _tipIncluded = RegExp(
    r'(con|c/|\+|incl\.?|including|with|mas|más)\s*(la\s*)?'
    r'(propina|tip|servicio|service)',
    caseSensitive: false,
  );

  static final RegExp _subtotalRow =
      RegExp(r'sub\s*-?\s*t(o)?t(a)?l\b', caseSensitive: false);
  static final RegExp _taxRow = RegExp(
    r'\b(iva|i\.v\.a|tax|vat|igv|itbms|isv|impuesto|igtf|ieps)\b',
    caseSensitive: false,
  );
  static final RegExp _taxBase =
      RegExp(r'\b(bi|base|exento|exempt|incluido|included)\b', caseSensitive: false);
  static final RegExp _paidRow = RegExp(
    r'punto\s*de\s*venta|tarjeta|\bcard\b|efectivo|\bcash\b|\bvisa\b|'
    r'master|d[eé]bito|cr[eé]dito|amex',
    caseSensitive: false,
  );
  static final RegExp _changeRow =
      RegExp(r'^\s*(su\s*)?(cambio|change|vuelto)\b', caseSensitive: false);

  static bool _near(int a, int b) => (a - b).abs() <= 2;

  /// Same number of digits and at most two differing: the kind of mistake
  /// OCR makes with slashed or faded zeros (0/8/6).
  static bool _looksMisread(int a, int b) {
    final x = a.toString();
    final y = b.toString();
    if (x.length != y.length) return false;
    const lookalikes = '035689';
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      if (x[i] == y[i]) continue;
      if (!lookalikes.contains(x[i]) || !lookalikes.contains(y[i])) return false;
      diff++;
    }
    return diff > 0 && diff <= 2;
  }

  /// A card-terminal slip line with the amount charged ("MONTO: Bs 76.337,31").
  static final RegExp _chargedRow = RegExp(
    r'^\s*(monto|importe|amount|cargo|total\s*cobrado|amount\s*charged)\b',
    caseSensitive: false,
  );
  static final RegExp _cardSlip = RegExp(
    r'aprobad|approved|autoriz|authori[sz]|\baid\b|tarjeta|\bcard\b|\*{4}',
    caseSensitive: false,
  );

  /// A card payment line on the bill ("PUNTO DE VENTA", "VISA 471.35").
  static final RegExp _cardPaidRow = RegExp(
    r'punto\s*de\s*venta|tarjeta|\bcard\b|\bvisa\b|master|amex|'
    r'd[eé]bito|cr[eé]dito|\bpos\b|freedom\s*pay',
    caseSensitive: false,
  );

  /// Cash handed over (change comes back), so never the amount spent.
  static final RegExp _cashRow = RegExp(
    r'efectivo|\bcash\b|recibido|tendered|pago\s*con|su\s*pago|cambio|'
    r'change\b|vuelto',
    caseSensitive: false,
  );

  /// The last amount with decimals on a row; whole numbers on payment lines
  /// are usually card digits or references.
  int? _lastDecimalAmount(String row, int exponent) {
    String? token;
    for (final m in _amountToken.allMatches(row)) {
      if (RegExp(r'[.,]\d{1,3}$').hasMatch(m[0]!)) token = m[0];
    }
    return token == null ? null : Money.parseMinor(token, exponent: exponent);
  }

  /// The most paid by card, tip included: what the bank statement shows and
  /// what gets claimed. Capped at twice the bill to ignore misreads.
  int? _charged(List<String> rows, int exponent, int? bill) {
    final slip = _cardSlip.hasMatch(rows.join('\n'));
    int? charged;
    for (final row in rows) {
      if (_cashRow.hasMatch(row)) continue;
      final isCharge = (slip && _chargedRow.hasMatch(row)) ||
          _cardPaidRow.hasMatch(row);
      if (!isCharge) continue;
      final v = _lastDecimalAmount(row, exponent);
      if (v != null && v > 0 && (charged == null || v > charged)) charged = v;
    }
    if (charged == null) return null;
    if (bill == null) return charged;
    // A cent or two over is rounding ("PUNTO DE VENTA 70.278,80"), not a tip.
    final margin = bill ~/ 100 > 2 ? bill ~/ 100 : 2;
    return charged > bill + margin && charged <= bill * 2 ? charged : null;
  }

  /// The amount for the claim: the highest money amount actually paid. That
  /// is the card charge with tip when one is shown, otherwise the bill total
  /// (which already prefers "total con propina").
  (int?, bool) _checkedTotal(List<String> rows, int exponent) {
    final (bill, doubtful) = _billTotal(rows, exponent);
    final charged = _charged(rows, exponent, bill);
    return charged != null ? (charged, false) : (bill, doubtful);
  }

  /// The bill total and whether it needs checking.
  ///
  /// A receipt states its total several ways: beside the word "total", as
  /// subtotal plus tax, as the sum of the item prices, as the amount paid,
  /// and often in words. Any two that agree settle it. A lone reading that
  /// nothing else supports is kept only if it is believable, and flagged
  /// when there is a reason to doubt it.
  (int?, bool) _billTotal(List<String> rows, int exponent) {
    final priced = _pricedRows(rows, exponent);
    final words = AmountInWords.find(rows);
    bool inWords(int v) => words.any((w) => w.matches(v, exponent));

    var subtotal = 0;
    var tax = 0;
    var sawTax = false;
    var change = 0;
    final paid = <int>[];
    for (final row in rows) {
      final v = _lastAmount(row, exponent);
      if (v == null || v <= 0) continue;
      if (_subtotalRow.hasMatch(row)) {
        if (v > subtotal) subtotal = v;
      } else if (_taxRow.hasMatch(row) && !_taxBase.hasMatch(row)) {
        tax += v;
        sawTax = true;
      } else if (_changeRow.hasMatch(row)) {
        change = v;
      } else if (_paidRow.hasMatch(row)) {
        paid.add(v);
      }
    }
    final computed = subtotal > 0 && sawTax ? subtotal + tax : null;
    final paidNet = [for (final p in paid) p - change];

    // The subtotal is a floor: a "total" below it is a misread (often the tip).
    final candidates = _keywordTotals(rows, exponent, subtotal);
    // Tips and service charges printed on their own rows: the gap between
    // the items (or the subtotal) and a total that includes them.
    var tips = 0;
    for (final row in rows) {
      if (!_tipOnly.hasMatch(row) || _tipIncluded.hasMatch(row)) continue;
      if (_totalPriority(row) >= 0 || _subtotalRow.hasMatch(row)) continue;
      final v = _lastDecimalAmount(row, exponent);
      if (v != null && v > 0) tips += v;
    }

    // What the item prices above a row add up to. The last one is left out
    // when it is the sum of the others: a subtotal whose label was misread.
    // [signless] reads every "$" taken for a 5 or 8 as a "$" ("8360.00" as
    // 360.00).
    int? itemsAbove(int row, {bool signless = false}) {
      final above = [
        for (final item in priced)
          if (item.row < row)
            signless && item.signless != null ? item.signless! : item.amount,
      ];
      if (above.isEmpty) return null;
      var sum = 0;
      for (final amount in above) {
        sum += amount;
      }
      final last = above.last;
      if (above.length >= 3 && sum - last == last) sum = last;
      return sum > 0 ? sum : null;
    }

    // Readings of the receipt independent of the item lines.
    bool backedByTotals(int amount) {
      if (_ladder(rows, exponent, amount)) return true;
      if (computed != null &&
          (_near(computed, amount) ||
              (tips > 0 && _near(computed + tips, amount)))) {
        return true;
      }
      if (computed == null && subtotal > 0 && tips > 0) {
        if (_near(subtotal + tips, amount)) return true;
      }
      if (paidNet.any((p) => _near(p, amount))) return true;
      return inWords(amount);
    }

    // The item lines add up to it (with any tip or service charge).
    bool backedByItems(int amount, int row) {
      for (final items in [itemsAbove(row), itemsAbove(row, signless: true)]) {
        if (items == null) continue;
        if (_near(items, amount)) return true;
        if (tips > 0 && _near(items + tips, amount)) return true;
      }
      return false;
    }

    // Subtotal plus tax gives a different amount, so items that agree with
    // the figure may share its misread ("$528.00" and "$818.00" for 520 and
    // 810).
    bool contradicted(int amount) =>
        computed != null &&
        !_near(computed, amount) &&
        !(tips > 0 && _near(computed + tips, amount));

    // Without a discount a total cannot be less than one of the items, so a
    // smaller "total" is a count of something or a misread. Unless the
    // receipt's own sums back it: then the item is the misread.
    final discounted = rows.any(_discountRow.hasMatch);
    _Candidate? pick;
    var belowAnItem = false;
    for (final c in candidates) {
      belowAnItem = false;
      if (!discounted) {
        var dearest = 0;
        for (final item in priced) {
          if (item.row < c.row && item.amount > dearest) dearest = item.amount;
        }
        if (c.amount < dearest &&
            !backedByTotals(c.amount) &&
            !backedByItems(c.amount, c.row)) {
          // A bare number is dropped; a proper money amount is kept, flagged.
          if (c.weak || c.priority <= _goodsTotalPriority) continue;
          belowAnItem = true;
        }
      }
      pick = c;
      break;
    }

    if (pick != null) {
      final signless = pick.signless;
      if (backedByTotals(pick.amount)) return (pick.amount, false);
      // "Total 53,760.00" where the 5 was the "$".
      if (signless != null && backedByTotals(signless)) {
        return (signless, false);
      }
      if (!contradicted(pick.amount) && backedByItems(pick.amount, pick.row)) {
        return (pick.amount, false);
      }
      if (signless != null &&
          !contradicted(signless) &&
          backedByItems(signless, pick.row)) {
        return (signless, false);
      }
      // The figure plus the printed tip is an amount further down: the total
      // with tip, its label lost ("IMPORTE 1,250.00 / PROPINA 187.50 /
      // T0TAL 1,437.50").
      if (tips > 0) {
        final later = _decimalAmounts(rows.sublist(pick.row + 1), exponent);
        for (final amount in later) {
          if (_near(amount, pick.amount + tips)) return (amount, false);
        }
      }
    }

    // A card payment that the items add up to ("VISA CREDITO 211.00" for
    // 114.00 + 97.00) is the bill, whatever a damaged total row says.
    for (final p in paidNet) {
      if (p > 0 &&
          p != pick?.amount &&
          !contradicted(p) &&
          backedByItems(p, rows.length)) {
        return (p, false);
      }
    }

    // ---- the amount in words picks between printed totals, or stands in
    final formal = [for (final w in words) if (w.formal) w];
    for (final w in formal) {
      for (final c in candidates) {
        if (!w.matches(c.amount, exponent)) continue;
        // The words give the bill; a bigger total after it (or one that says
        // it includes the tip) is what was paid.
        if (pick != null &&
            pick.amount > c.amount &&
            (pick.priority >= 100 || pick.row > c.row)) {
          return (pick.amount, false);
        }
        return (c.amount, false);
      }
    }
    final itemsTotal = _itemsTotal(priced);
    final printedAmounts = _decimalAmounts(rows, exponent);
    for (final w in formal) {
      if (itemsTotal != null && w.matches(itemsTotal, exponent)) {
        return (itemsTotal, false);
      }
      if (computed != null && w.matches(computed, exponent)) {
        return (computed, false);
      }
      for (final amount in printedAmounts) {
        if (w.matches(amount, exponent)) return (amount, false);
      }
    }

    if (computed != null) {
      if (paidNet.any((p) => _near(p, computed))) return (computed, false);
      if (pick != null && _looksMisread(pick.amount, computed)) {
        return (computed, true);
      }
    }
    if (pick != null) {
      for (final p in paidNet) {
        if (_looksMisread(pick.amount, p)) return (pick.amount, true);
      }
    }

    // ---- words that no figure backs. Read cleanly, they are harder to get
    // wrong than digits: one misread letter makes a non-word, one misread
    // digit makes another number.
    WordsAmount? stated;
    for (final w in formal) {
      if (w.exact) {
        stated = w;
        break;
      }
    }
    if (stated != null) {
      final value = stated.toMinor(exponent);
      if (pick == null || pick.weak || belowAnItem) return (value, true);
      // The figures and the words differ by a look-alike digit. Either a
      // digit was misread or a faint word was lost: ask.
      if (_looksMisread(pick.amount, value)) return (value, true);
      // A little more than the words say, on a receipt with a tip: the tip.
      final tipped = pick.priority >= 100 || rows.any(_tipOnly.hasMatch);
      if (tipped && pick.amount > value && pick.amount <= value + value ~/ 3) {
        return (pick.amount, false);
      }
      return (value, true);
    }

    if (pick != null) {
      if (pick.weak || belowAnItem) return (pick.amount, true);
      // One digit away from the sum of the items: one of them was misread.
      // (With a tip or service row the gap is that charge, not a misread.)
      final items = itemsAbove(pick.row);
      if (tips == 0 && items != null && _looksMisread(pick.amount, items)) {
        return (pick.amount, true);
      }
      return (pick.amount, false);
    }
    return _unlabelledTotal(
      rows,
      exponent,
      priced: priced,
      computed: computed,
      paidNet: paidNet,
      inWords: inWords,
    );
  }

  /// Rows that state a total, best first.
  List<_Candidate> _keywordTotals(List<String> rows, int exponent, int floor) {
    // A bare whole number is suspect on a receipt that prints its money with
    // decimals: "Total de productos: 24" among prices like "$1,170.00".
    var decimalRows = 0;
    for (final row in rows) {
      if (_referenceRow.hasMatch(row) ||
          _phoneRow.hasMatch(row) ||
          _datesIn(row).isNotEmpty) {
        continue;
      }
      if (RegExp(r'\d[.,]\d{2}(?!\d)').hasMatch(row)) decimalRows++;
    }
    final out = <_Candidate>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (_notTotal.hasMatch(row) || _tenderLine.hasMatch(row)) continue;
      if (_tipOnly.hasMatch(row) && !_tipIncluded.hasMatch(row)) continue;
      var priority = _totalPriority(row);
      // "T0TAL CON PROPINA": the tip-inclusive total, whatever OCR made of
      // the word "total".
      if (priority < 0 && _tipIncluded.hasMatch(row)) priority = 100;
      if (priority < 0) continue;
      var read = _lastAmountToken(row, exponent);
      if (_countLabel.hasMatch(row)) {
        // A count, unless it is plainly money ("TOTAL PRODUCTOS $350.00").
        if (read == null || read.bare) continue;
        priority = _goodsTotalPriority;
      } else if (read == null &&
          i + 1 < rows.length &&
          TextNormaliser.letterCount(rows[i + 1]) < 4) {
        read = _lastAmountToken(rows[i + 1], exponent);
      }
      if (read == null) continue;
      if (read.amount <= 0 || read.amount < floor) continue;
      out.add(_Candidate(
        row: i,
        priority: priority,
        amount: read.amount,
        signless: read.signless,
        weak: read.bare &&
            exponent > 0 &&
            (decimalRows >= 2 || _oddTotalLabel(row)),
      ));
    }
    out.sort((a, b) {
      if (a.priority != b.priority) return b.priority.compareTo(a.priority);
      if (a.weak != b.weak) return a.weak ? 1 : -1;
      if (a.amount != b.amount) return b.amount.compareTo(a.amount);
      return a.row.compareTo(b.row);
    });
    return out;
  }

  /// Words that can follow "total" on a row that is still about money.
  static final RegExp _totalQualifier = RegExp(
    r'^(incl\w*|pagar|pagado|pago|cobrar|cobrado|neto|general|final|ventas?|'
    r'compra|cuenta|consumo|factura|pedido|orden|nota|ticket|servicio|'
    r'propina|impuestos?|amount|sales?|bill|order|paid|payable|pesos?|'
    r'd[oó]lares|bol[ií]vares|importe|monto|euros?|gran|grand|with|includ\w*)$',
    caseSensitive: false,
  );

  /// "Total de (something else): 24": a total of a thing this parser does
  /// not know, so a bare number after it may not be money.
  static bool _oddTotalLabel(String row) {
    final label = RegExp(r'\btotal\b', caseSensitive: false).firstMatch(row);
    if (label == null) return false;
    final rest = row.substring(label.end).split(RegExp(r'\d')).first;
    for (final word in RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]{4,}').allMatches(rest)) {
      if (!_totalQualifier.hasMatch(word[0]!)) return true;
    }
    return false;
  }

  static final RegExp _trailingJunk = RegExp(r'^\s*-?\s*[A-Za-z]?[^A-Za-z0-9]*$');
  static final RegExp _leadingQuantity = RegExp(r'^\s*(\d{1,3})\s+(?=\D)');
  static final RegExp _unitPriceValue = RegExp(r'@\s?[$£€]?\s?(\d[\d.,]*)');

  /// Rows that carry a price, in reading order. Totals, tax, tips, payments,
  /// counts and reference rows are left out; discounts are negative.
  List<_Priced> _pricedRows(List<String> rows, int exponent) {
    if (exponent == 0) return const [];
    final decimals = RegExp('[.,]\\d{$exponent}\$');
    final out = <_Priced>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i].replaceAll(_unitPrice, ' ');
      final moneyOff = _moneyOffRow.hasMatch(row);
      if (_totalPriority(row) >= 0 ||
          _subtotalRow.hasMatch(row) ||
          (row.contains('%') && !moneyOff) ||
          _unitPriceRow.hasMatch(row) ||
          _countLabel.hasMatch(row) ||
          _taxRow.hasMatch(row) ||
          _taxBase.hasMatch(row) ||
          _tipOnly.hasMatch(row) ||
          _tenderLine.hasMatch(row) ||
          _paidRow.hasMatch(row) ||
          _cardPaidRow.hasMatch(row) ||
          _chargedRow.hasMatch(row) ||
          _referenceRow.hasMatch(row) ||
          _datesIn(row).isNotEmpty) {
        continue;
      }
      RegExpMatch? last;
      for (final m in _amountToken.allMatches(row)) {
        last = m;
      }
      // The price is the last thing on the row ("12.35E" tax flags aside).
      if (last == null ||
          !decimals.hasMatch(last[0]!) ||
          !_trailingJunk.hasMatch(row.substring(last.end))) {
        continue;
      }
      var value = Money.parseMinor(last[0]!, exponent: exponent);
      if (value == null || value == 0) continue;
      var signless = _signless(row, last, exponent);
      // "1 Naranjada @$59.00  559.00": one at 59.00 is 59.00, so the first
      // 5 was the "$".
      final quantity = _leadingQuantity.firstMatch(rows[i]);
      final unit = _unitPriceValue.firstMatch(rows[i]);
      if (signless != null && quantity != null && unit != null) {
        final each = Money.parseMinor(unit[1]!, exponent: exponent);
        if (each != null && int.parse(quantity[1]!) * each == signless) {
          value = signless;
          signless = null;
        }
      }
      if (row.substring(last.end).contains('-') && value > 0) value = -value;
      if (value > 0 && moneyOff) value = -value;
      out.add(_Priced(i, value, value > 0 ? signless : null));
    }
    return out;
  }

  /// The last priced row when it equals the sum of those above it: a total
  /// row whose label OCR could not read ("Tota1 $3,760.00").
  static int? _unlabelledSum(List<_Priced> priced) {
    if (priced.length < 3) return null;
    var above = 0;
    for (var i = 0; i < priced.length - 1; i++) {
      above += priced[i].amount;
    }
    if (above <= 0) return null;
    final last = priced.last;
    if (last.amount == above || last.signless == above) return above;
    return null;
  }

  /// What the items add up to, when at least two were read.
  static int? _itemsTotal(List<_Priced> priced) {
    final sum = _unlabelledSum(priced);
    if (sum != null) return sum;
    if (priced.length < 2) return null;
    var total = 0;
    for (final item in priced) {
      total += item.amount;
    }
    return total > 0 ? total : null;
  }

  /// No row says "total": work the amount out from what is printed.
  (int?, bool) _unlabelledTotal(
    List<String> rows,
    int exponent, {
    required List<_Priced> priced,
    required int? computed,
    required List<int> paidNet,
    required bool Function(int) inWords,
  }) {
    final sum = _unlabelledSum(priced);
    if (sum != null) {
      // A bigger amount further down (a total with tip whose label is lost)
      // may be what was paid.
      final after = _decimalAmounts(rows.sublist(priced.last.row + 1), exponent);
      return (sum, after.any((a) => a > sum));
    }
    final amounts = _decimalAmounts(rows, exponent);
    if (amounts.isEmpty) return (null, false);
    final largest = amounts.reduce((a, b) => a > b ? a : b);
    if (_ladder(rows, exponent, largest)) return (largest, false);
    var items = 0;
    for (final item in priced) {
      items += item.amount;
    }
    if (amounts.toSet().length == 1 ||
        (computed != null && _near(computed, largest)) ||
        paidNet.any((p) => _near(p, largest)) ||
        inWords(largest) ||
        // Printed somewhere other than its own row, yet it is what the
        // items add up to.
        (priced.length >= 2 && items == largest)) {
      return (largest, false);
    }
    // The dearest line is an item with others after it, so the total itself
    // was not read: the items added up are the better guess.
    if (priced.length >= 2 &&
        priced.last.amount != largest &&
        items > largest) {
      return (items, true);
    }
    return (largest, true);
  }

  /// Whether the printed amounts climb to [total] the way a bill does, even
  /// with their labels lost: items that add up to a subtotal, then the
  /// subtotal plus a tip or tax gives the total ("2.21 2.21 12.35 11.46 /
  /// 28.23 / 3.19 / 31.42"). Uses the last amount on each row, in order.
  bool _ladder(List<String> rows, int exponent, int total) {
    final seq = <int>[];
    for (final row in rows) {
      if (_tenderLine.hasMatch(row) || _idLine.hasMatch(row)) continue;
      if (_datesIn(row).isNotEmpty) continue;
      final v = _lastDecimalAmount(row.replaceAll(_clockTime, ' '), exponent);
      if (v != null && v > 0) seq.add(v);
    }
    final t = seq.lastIndexOf(total);
    if (t < 3) return false;
    for (var k = 2; k < t; k++) {
      final subtotal = seq[k];
      var tipFound = false;
      for (var m = k + 1; m < t; m++) {
        if (subtotal + seq[m] == total) tipFound = true;
      }
      if (tipFound && _someAddUpTo(seq.sublist(0, k), subtotal)) return true;
    }
    return false;
  }

  /// Whether two or more of the [amounts] nearest the end add up exactly to
  /// [target]. Not just a neat run: on a tilted photo an item's unit price
  /// and its line total land on separate rows, so each price shows twice.
  static bool _someAddUpTo(List<int> amounts, int target) {
    final window =
        amounts.length > 20 ? amounts.sublist(amounts.length - 20) : amounts;
    final one = <int>{};
    final many = <int>{};
    for (final a in window.reversed) {
      if (a > target) continue;
      final newMany = <int>{
        for (final s in one) if (s + a <= target) s + a,
        for (final s in many) if (s + a <= target) s + a,
      };
      many.addAll(newMany);
      one.add(a);
      if (many.contains(target)) return true;
      if (many.length > 50000) return false;
    }
    return false;
  }

  /// Every two-decimal amount not on a tender or reference line.
  List<int> _decimalAmounts(List<String> rows, int exponent) {
    final out = <int>[];
    for (final row in rows) {
      if (_tenderLine.hasMatch(row) || _idLine.hasMatch(row)) continue;
      for (final m in _amountToken.allMatches(row)) {
        final token = m[0]!;
        if (!RegExp(r'[.,]\d{2}$').hasMatch(token)) continue;
        final value = Money.parseMinor(token, exponent: exponent);
        if (value != null) out.add(value);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- currency

  static final RegExp _codeNearAmount = RegExp(
    '\\b(${Currencies.common.join('|')})\\b\\s?[:=]?\\s?\\\$?\\s?\\d|'
    '\\d[.,]\\d{2}\\s?(${Currencies.common.join('|')})\\b',
  );
  static final RegExp _bolivar = RegExp(r'\bBs\.?\s?S?\.?\s?\d');
  static final RegExp _monedaNacional = RegExp(r'\bM\.\s?N\.?');

  (String, bool) _detectCurrency(List<String> rows) {
    final scores = <String, int>{};
    for (final row in rows) {
      final weight = _totalPriority(row) >= 0 ? 3 : 1;
      for (final m in _codeNearAmount.allMatches(row)) {
        final code = m[1] ?? m[2];
        if (code == null) continue;
        scores[code] = (scores[code] ?? 0) + weight;
      }
    }
    if (scores.isNotEmpty) {
      final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
      return (best.key, true);
    }
    final joined = rows.join('\n');
    for (final entry in Currencies.unambiguousSymbols.entries) {
      if (entry.key == 'S/') {
        // Peruvian sol, but not "S/N" (sin número) in an address.
        if (RegExp(r'\bS/\.?\s?\d').hasMatch(joined)) return ('PEN', true);
        continue;
      }
      if (joined.contains(entry.key)) return (entry.value, true);
    }
    if (_bolivar.hasMatch(joined)) return ('VES', true);
    if (_monedaNacional.hasMatch(joined)) return (defaultCurrency, true);
    return (defaultCurrency, false);
  }
}

/// An amount read from a row.
class _Reading {
  const _Reading(this.amount, {required this.bare, this.signless});

  final int amount;

  /// A whole number with no decimals or separators ("24").
  final bool bare;

  /// The amount if its first digit was really a misread "$".
  final int? signless;
}

/// A row that carries a price.
class _Priced {
  const _Priced(this.row, this.amount, this.signless);

  final int row;
  final int amount;
  final int? signless;
}

/// A row that claims to be the total.
class _Candidate {
  const _Candidate({
    required this.row,
    required this.priority,
    required this.amount,
    required this.weak,
    this.signless,
  });

  final int row;
  final int priority;
  final int amount;

  /// A bare whole number on a receipt whose prices have decimals.
  final bool weak;

  /// The amount if its first digit was really a misread "$".
  final int? signless;
}

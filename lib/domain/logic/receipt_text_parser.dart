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
        _joinSplitNumbers(foldStrayAccents(
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
              (foldStrayAccents(TextNormaliser.collapseSpaces(t)), h),
      ]);
    }
    // The amount and the currency are read from rows tidied for money; the
    // name, date and time from the rows as they are.
    final money = [for (final row in rows) _tidyMoneyRow(row)];
    final ((currency, detected), otherCurrencies) = _detectCurrency(money);
    final exponent = Currencies.exponentOf(currency);
    final (amount, doubtful) = _checkedTotal(
      _pairLabelBlocks(
        _ownCurrencyRows(money, currency, otherCurrencies),
        exponent,
      ),
      exponent,
    );
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

  /// "Grandę" -> "Grande": marks a crease or a tear adds that no language
  /// on these receipts uses.
  static String foldStrayAccents(String text) {
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
          // "19 nov 2026, 21:14": a year, a comma and the time.
          if (RegExp(r'^\d?:\d{2}(?!\d)').hasMatch(row.substring(m.end))) {
            return m[0]!;
          }
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

  /// Dots, dashes or underscores leading from a label to its amount:
  /// "TOTAL..........475.00", "TOTAL ____ 475.00".
  static final RegExp _leaders = RegExp(r'(?:\s?\.){2,}\s?|[-_]{2,}');

  /// "Q.125.00", "Bs.1.295,60", "B/.19.80", "L.350.00": the full stop ends
  /// the abbreviation, it is not part of the number. Not after a lone O, I
  /// or l, which are more often a misread 0 or 1 ("1O.50").
  static final RegExp _abbreviationDot =
      RegExp(r'(?<=[A-HJ-NP-Za-km-np-z/])\.(?=\d)');

  /// "T O T A L": a word printed with a space between its letters.
  static final RegExp _spacedWord =
      RegExp(r'(?<![A-Za-z])(?:[A-Za-z] ){3,}[A-Za-z](?![A-Za-z])');

  /// "$475 00": the decimal point read as a space, after a currency sign.
  static final RegExp _spaceForPoint = RegExp(
    r'([$£€]\s?\d[\d,]*) (\d{2})(?![\d.,:/%-])(?!\s+\d)',
  );

  /// A row made ready for reading money: leaders dropped, an abbreviation's
  /// full stop parted from the figures, spaced-out words closed up.
  static String _tidyMoneyRow(String row) {
    var text = row.replaceAll(_leaders, ' ').replaceAll(_abbreviationDot, '. ');
    text = text.replaceAllMapped(_spacedWord, (m) {
      final word = m[0]!.replaceAll(' ', '');
      // "T O T A L A P A G A R": the spaces between words are lost too.
      return word.replaceFirstMapped(
        RegExp(r'^(sub)?total(?=[a-z])', caseSensitive: false),
        (t) => '${t[0]} ',
      );
    });
    text = text.replaceAllMapped(_spaceForPoint, (m) => '${m[1]}.${m[2]}');
    return TextNormaliser.collapseSpaces(text);
  }

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
    r'raz[oó]n\s*social|gen[eé]rico|huesped|hu[eé]sped|suc\b|sucursal|'
    r'recepci[oó]n|por\s+favor|please|ay[uú]dan|encuesta|survey|escane|'
    r'califica|eval[uú]a|opini[oó]n|siempre\s+le|lo\s+esperamos)',
    caseSensitive: false,
  );

  /// Staff, table, payment and service rows ("LE ATENDIO MARIA", "Server:
  /// Mike", "TARJETA ************1234", "PARA LLEVAR", "CASA MATRIZ", "VAT
  /// NO. 000"), and the place a shop is in rather than the shop ("CENTRO
  /// COMERCIAL EJEMPLO", "AEROPUERTO INTERNACIONAL").
  static final RegExp _serviceRow = RegExp(
    r'^((le\s+)?atendi[oó]|atendido|vendedor|server\b|host\b|guests?\b|'
    // "OPERADOR: 12" is staff; "OPERADORA EJEMPLO SA DE CV" is a company.
    r'covers\b|turno\b|titular|operador\b|usuario|empleado|tarjeta|card\b|'
    r'efectivo|cash\b|contado|pedido|para\s+llevar|llevar\b|to\s+go\b|'
    r'take\s*(out|away)|dine\s+in|eat\s+in|comer\s+aqu[ií]|(casa\s+)?matriz|'
    r'vuelva|conserve|muchas\s+gracias|vat\b|tax\b|centro\s+comercial|'
    r'c\.\s?c\.|aeropuerto|airport)',
    caseSensitive: false,
  );

  /// A branch or till number ("Restaurante #12345", "TIENDA 1234", "Store
  /// 1234", "UNIDAD 1234 EJEMPLO").
  static final RegExp _branchRow = RegExp(
    r'^(tienda|store|shop|unidad|unit|restaurante?|complejo|site|local|'
    r'estaci[oó]n|station)\s*(no\.?|n[uú]m\.?|n[°º]|:)?\s*(#\s*\d+|\d{2,})\b',
    caseSensitive: false,
  );

  /// A field under its label ("Vendedor: 12 JUAN", "TURNO: MATUTINO", "VAT
  /// NUMBER: GB 000 0000 00"): whatever follows the colon is not the name.
  static final RegExp _fieldRow = RegExp(r"^[A-Za-zÀ-ÿ.#/º°' ]{2,24}:");

  /// The one field that is the name: "COMERCIO: TACOS EJEMPLO", "NOMBRE
  /// COMERCIAL: CAFE EJEMPLO", "Merchant: EXAMPLE CAFE".
  static final RegExp _merchantLabel = RegExp(
    r'^\W*(?:nombre\s+(?:comercial|del\s+(?:comercio|establecimiento))|'
    r'comercio|establecimiento|negocio|merchant(?:\s+name)?)\s*:\s*'
    r'(?:\d+\s+)?(\S.*)$',
    caseSensitive: false,
  );

  /// Words for the paper itself, wherever they stand on the row ("DOCUMENTO
  /// TRIBUTARIO ELECTRONICO", "SALES RECEIPT", "ESTE NO ES UN COMPROBANTE
  /// FISCAL", "MERCHANT COPY", "CONSUMIDOR FINAL").
  static final RegExp _documentWord = RegExp(
    r'\b(documento|comprobante|factura|tiquete|boleta|boleto|recibo|receipt|'
    r'invoice|voucher|ticket|pagar[eé]|reimpresi[oó]n|reimpreso|reprint|'
    r'duplicado|duplicate|copia|guest\s+check|consumidor\s+final|'
    r'nota\s+fiscal|cupom\s+fiscal|danfe|'
    r'p[uú]blico\s+en\s+general|no\s+fiscal|'
    r'(customer|merchant|cardholder|client|store|bank)\s+copy)\b',
    caseSensitive: false,
  );

  /// The seller's tax regime or status ("PERSONA MORAL REGIMEN GENERAL DE
  /// LEY", "SUJETO A PAGOS TRIMESTRALES ISR", "RESPONSABLE DE IVA",
  /// "PEQUENO CONTRIBUYENTE"), also when OCR hurt it ("REGTMEN").
  static final RegExp _taxStatus = RegExp(
    r'r[eé]g[it]men|contribuyente|retenci[oó]n|retenedor|\bisr\b|\biva\b|'
    r'persona\s+(mora|f[ií]sica)|general\s+de\s+ley|incorporaci[oó]n\s+fiscal|'
    r'actividad\s+(econ[oó]mica|empresarial)',
    caseSensitive: false,
  );

  /// Requests printed where the logo was not read ("TU OPINION NOS
  /// IMPORTA", "Tell us about your visit").
  static final RegExp _request = RegExp(
    r'opini[oó]n|encuesta|survey|feedback|tell\s+us|your\s+(visit|opinion)|'
    r'how\s+did\s+we',
    caseSensitive: false,
  );

  /// Banks and card processors that head a card slip above the shop ("BAC
  /// CREDOMATIC", "BANCO INDUSTRIAL", "VISANET GUATEMALA", "AMERICAN
  /// EXPRESS"). More of them are in [_merchantNoise].
  static final RegExp _acquirer = RegExp(
    r'^(visanet|neonet|visa\b|master\s?card|american\s+express|amex\b|bac\b|'
    r'banrural|bancolombia|banesco|bancaribe|banplus|bancoppel|bantrab|'
    r'(banco|bank)\s+(of\b|de\b|del\b|industrial|agr[ií]cola|azteca|'
    r'promerica|cuscatl[aá]n|atl[aá]ntida|ficohsa|popular|nacional|mercantil|'
    r'provincial|davivienda|bicentenario|exterior|activo|occidente|'
    r'inmobiliario|internacional|g\s*&?\s*t|uni[oó]n|ahorro)|'
    r'g\s*&\s*t\s+continental|promerica|davivienda|serfinsa|redeban|'
    r'credibanco|first\s*data|fiserv|elavon|worldpay|global\s+payments|'
    r'barclaycard|billpocket|izettle|stripe\b|paypal|e-?global|kushki|'
    r'pagadito|transbank|multipagos|punto\s+de\s+venta)',
    caseSensitive: false,
  );

  /// A row that ends in a price is an item or a sum ("1 CAFE AMERICANO
  /// 45.00", "REFRESCO $18.00"), not a name. A dotted phone number
  /// ("55.12.34.56") is not a price.
  static final RegExp _pricedRow =
      RegExp(r'(?<![\d.,])\d+(?:[.,]\d{3})*[.,]\d{2}\s*[A-Za-z]?\s*$');

  /// A hidden card or account number ("************1234", "XXXX1234").
  static final RegExp _maskedNumber =
      RegExp(r'\*{3,}|x{4,}\d', caseSensitive: false);

  /// "TOTAL 70.00": the name is never under the sums.
  static final RegExp _totalRow =
      RegExp(r'^\W*(sub\s*-?\s*)?total\b', caseSensitive: false);

  static final RegExp _legalSuffix = RegExp(
    r'[,\s]+(S[.,]?\s?A[.,]?(\s?[PB][.,]?(\s?I[.,]?)?)?(\s?DE\s?C[.,]?\s?V\.?)?|'
    r'S\.?\s?DE\s?R\.?\s?[LI1]\.?(\s?DE\s?C\.?\s?V\.?)?|'
    r'SOCIEDAD\s+AN[OÓ]NIMA(\s+DE\s+CAPITAL\s+VARIABLE)?|'
    r'COMPA[NÑ][IÍ]A\s+AN[OÓ]NIMA|S\.?\s?R\.?\s?L\.?|C\.\s?A\.?|LTDA?\.?|'
    r'LIMITADA|LIMITED|PLC|INC\.?|LLC|CORP\.?|CORPORATION|S\.?A\.?S\.?|'
    r'S\.?\s?C\.?[\s.\-]?S\.?|GMBH)\s*$',
    caseSensitive: false,
  );

  /// Well-known brands, checked before guessing from the layout. App
  /// receipts (Uber, DiDi…) put a greeting in the biggest text, not the name.
  /// These may stand anywhere on the receipt, so each is a name nothing else
  /// is called: ambiguous words (e.g. "Copa", "United", "Delta") need a
  /// qualifier, and short or everyday ones are in [_headerBrands].
  static const List<(String, String)> _brandNames = [
    // Apps first: their receipts name restaurants and hotels as well.
    (r'uber\s*eats', 'Uber Eats'),
    ('uber', 'Uber'),
    (r'didi\s*food', 'DiDi Food'),
    ('didi', 'DiDi'),
    ('cabify', 'Cabify'),
    ('rappi', 'Rappi'),
    ('lyft', 'Lyft'),
    ('airbnb', 'Airbnb'),
    ('indrive', 'inDrive'),
    (r'pedidos\s?ya', 'PedidosYa'),
    ('deliveroo', 'Deliveroo'),
    (r'booking\.com', 'Booking.com'),
    ('expedia', 'Expedia'),
    // Airlines.
    (r'aerom[eé]xico', 'Aeroméxico'),
    ('volaris', 'Volaris'),
    (r'viva\s*aerobus', 'Viva Aerobus'),
    ('avianca', 'Avianca'),
    (r'copa\s*airlines', 'Copa Airlines'),
    (r'latam\s*airlines', 'LATAM Airlines'),
    (r'tag\s*airlines', 'TAG Airlines'),
    (r'british\s*airways', 'British Airways'),
    ('iberia', 'Iberia'),
    (r'american\s*airlines', 'American Airlines'),
    (r'united\s*airlines', 'United Airlines'),
    (r'delta\s*air\s*lines', 'Delta Air Lines'),
    ('jetblue', 'JetBlue'),
    (r'spirit\s*airlines', 'Spirit Airlines'),
    (r'southwest\s*airlines', 'Southwest Airlines'),
    ('lufthansa', 'Lufthansa'),
    (r'air\s*france', 'Air France'),
    ('ryanair', 'Ryanair'),
    ('easyjet', 'easyJet'),
    // Coffee and bakeries.
    ('starbucks', 'Starbucks'),
    (r'costa\s*coffee', 'Costa Coffee'),
    (r'maison\s*kayser', 'Maison Kayser'),
    (r'tim\s*hortons', 'Tim Hortons'),
    (r'cielito\s*querido', 'Cielito Querido'),
    (r'punta\s*del\s*cielo', 'Punta del Cielo'),
    (r'juan\s*valdez', 'Juan Valdez'),
    (r'krispy\s*kreme', 'Krispy Kreme'),
    (r"dunkin'?", "Dunkin'"),
    (r'pret\s*a\s*manger', 'Pret A Manger'),
    (r'caf[eé]\s*barista', 'Café Barista'),
    (r'caff[eè]\s*nero', 'Caffè Nero'),
    ('greggs', 'Greggs'),
    ('caffenio', 'Caffenio'),
    (r'the\s*italian\s*coffee', 'The Italian Coffee Company'),
    // Shops, supermarkets and pharmacies.
    (r'oxxo\s*gas', 'OXXO Gas'),
    ('oxxo', 'OXXO'),
    (r'7[\s-]?eleven', '7-Eleven'),
    (r'wal[\s-]?mart', 'Walmart'),
    ('costco', 'Costco'),
    ('sanborns', 'Sanborns'),
    (r'bodega\s*aurrer[aá]', 'Bodega Aurrera'),
    (r"sam'?s\s*club", "Sam's Club"),
    ('chedraui', 'Chedraui'),
    ('soriana', 'Soriana'),
    (r'la\s*comer', 'La Comer'),
    ('superama', 'Superama'),
    ('pricesmart', 'PriceSmart'),
    (r'circle\s*k', 'Circle K'),
    (r'super\s*selectos', 'Super Selectos'),
    (r'despensa\s*familiar', 'Despensa Familiar'),
    (r'maxi\s*despensa', 'Maxi Despensa'),
    ('farmatodo', 'Farmatodo'),
    (r'central\s*madeirense', 'Central Madeirense'),
    ('carulla', 'Carulla'),
    ('tesco', 'Tesco'),
    (r"sainsbury'?s", "Sainsbury's"),
    ('waitrose', 'Waitrose'),
    ('morrisons', 'Morrisons'),
    (r'marks\s*(&|and)\s*spencer', 'Marks & Spencer'),
    (r'wh\s?smith', 'WHSmith'),
    ('walgreens', 'Walgreens'),
    (r'cvs\s*/?\s*pharmacy', 'CVS'),
    (r'duane\s*reade', 'Duane Reade'),
    (r'whole\s*foods', 'Whole Foods'),
    (r"trader\s*joe'?s", "Trader Joe's"),
    (r'palacio\s*de\s*hierro', 'Palacio de Hierro'),
    ('coppel', 'Coppel'),
    ('elektra', 'Elektra'),
    (r'office\s*depot', 'Office Depot'),
    ('officemax', 'OfficeMax'),
    (r'home\s*depot', 'Home Depot'),
    (r'best\s*buy', 'Best Buy'),
    ('cemaco', 'Cemaco'),
    ('steren', 'Steren'),
    ('miniso', 'Miniso'),
    ('dufry', 'Dufry'),
    (r'hudson\s*news', 'Hudson News'),
    (r'farmacias?\s*guadalajara', 'Farmacias Guadalajara'),
    (r'farmacias?\s*del\s*ahorro', 'Farmacias del Ahorro'),
    (r'farmacias?\s*similares', 'Farmacias Similares'),
    (r'farmacias?\s*benavides', 'Farmacias Benavides'),
    (r'farmacias?\s*san\s*pablo', 'Farmacia San Pablo'),
    (r'farmacias?\s*galeno', 'Farmacias Galeno'),
    (r'farmacias?\s*cruz\s*verde', 'Cruz Verde'),
    ('meykos', 'Meykos'),
    // Restaurants and fast food.
    (r"mc\s?donald'?s", "McDonald's"),
    (r'burger\s*king', 'Burger King'),
    // "KEC": the F of a thermal-printed KFC is often read as an E.
    ('k[fe]c', 'KFC'),
    (r'pizza\s*hut', 'Pizza Hut'),
    (r"domino'?s", "Domino's"),
    (r'little\s*caesars', 'Little Caesars'),
    (r"carl'?s\s*jr", "Carl's Jr."),
    (r'pollo\s*campero', 'Pollo Campero'),
    (r'pollo\s*brujo', 'Pollo Brujo'),
    (r'(pollo\s*)?pinulito', 'Pollo Pinulito'),
    (r'pollo\s*campestre', 'Pollo Campestre'),
    (r'el\s*pollo\s*loco', 'El Pollo Loco'),
    (r'taco\s*bell', 'Taco Bell'),
    (r"wendy'?s", "Wendy's"),
    (r"applebee'?s", "Applebee's"),
    (r"denny'?s", "Denny's"),
    (r'olive\s*garden', 'Olive Garden'),
    (r'panda\s*express', 'Panda Express'),
    ('popeyes', 'Popeyes'),
    (r'five\s*guys', 'Five Guys'),
    (r'shake\s*shack', 'Shake Shack'),
    (r'chick-?fil-?a', 'Chick-fil-A'),
    ('panera', 'Panera'),
    (r"nando'?s", "Nando's"),
    ('wagamama', 'Wagamama'),
    (r"p\.?\s?f\.?\s?chang'?s", "P.F. Chang's"),
    (r'california\s*pizza\s*kitchen', 'California Pizza Kitchen'),
    (r"italianni'?s", "Italianni's"),
    (r'la\s*casa\s*de\s*to[nñ]o', 'La Casa de Toño'),
    (r'sushi\s*itto', 'Sushi Itto'),
    (r'tre\s*fratelli', 'Tre Fratelli'),
    (r'crepes\s*(&|y|and)\s*waffles', 'Crepes & Waffles'),
    ('frisby', 'Frisby'),
    (r'tgi\s*friday', 'TGI Fridays'),
    ('hooters', 'Hooters'),
    (r'red\s*lobster', 'Red Lobster'),
    (r'dairy\s*queen', 'Dairy Queen'),
    (r'baskin\s*robbins', 'Baskin-Robbins'),
    ('cinnabon', 'Cinnabon'),
    (r"papa\s*john'?s", "Papa John's"),
    ('telepizza', 'Telepizza'),
    ('potzollcalli', 'Potzollcalli'),
    (r'bisquets\s*obreg[oó]n', 'Bisquets Obregón'),
    // Hotels and car hire.
    ('marriott', 'Marriott'),
    ('hilton', 'Hilton'),
    ('hyatt', 'Hyatt'),
    (r'holiday\s*inn', 'Holiday Inn'),
    (r'fiesta\s*inn', 'Fiesta Inn'),
    (r'fiesta\s*americana', 'Fiesta Americana'),
    (r'city\s*express', 'City Express'),
    (r'hampton\s*inn', 'Hampton Inn'),
    ('sheraton', 'Sheraton'),
    ('westin', 'Westin'),
    (r'crowne\s*plaza', 'Crowne Plaza'),
    (r'best\s*western', 'Best Western'),
    ('wyndham', 'Wyndham'),
    ('radisson', 'Radisson'),
    ('novotel', 'Novotel'),
    (r'premier\s*inn', 'Premier Inn'),
    ('travelodge', 'Travelodge'),
    ('doubletree', 'DoubleTree'),
    (r'embassy\s*suites', 'Embassy Suites'),
    ('hertz', 'Hertz'),
    ('europcar', 'Europcar'),
    (r'enterprise\s*rent', 'Enterprise'),
    (r'alamo\s*rent', 'Alamo'),
    (r'budget\s*rent', 'Budget'),
    (r'national\s*car\s*rental', 'National'),
    // Fuel, tolls, buses, trains, taxis, cinemas.
    ('pemex', 'Pemex'),
    ('texaco', 'Texaco'),
    ('chevron', 'Chevron'),
    (r'exxon(\s*mobil)?', 'Exxon'),
    (r'puma\s*energy', 'Puma Energy'),
    ('repsol', 'Repsol'),
    ('hidrosina', 'Hidrosina'),
    ('terpel', 'Terpel'),
    ('primax', 'Primax'),
    ('capufe', 'CAPUFE'),
    (r'primera\s*plus', 'Primera Plus'),
    (r'estrella\s*roja', 'Estrella Roja'),
    (r'estrella\s*de\s*oro', 'Estrella de Oro'),
    (r'omnibus\s*de\s*m[eé]xico', 'Omnibus de México'),
    (r'tica\s*bus', 'Tica Bus'),
    ('litegua', 'Litegua'),
    ('trainline', 'Trainline'),
    (r'transport\s*for\s*london', 'Transport for London'),
    (r'heathrow\s*express', 'Heathrow Express'),
    (r'gatwick\s*express', 'Gatwick Express'),
    (r'national\s*express', 'National Express'),
    ('amtrak', 'Amtrak'),
    (r'addison\s*lee', 'Addison Lee'),
    (r'yellow\s*cab', 'Yellow Cab'),
    (r'cin[eé]polis', 'Cinépolis'),
    ('cinemex', 'Cinemex'),
  ];

  static final List<(RegExp, String)> _brands = [
    for (final (pattern, name) in _brandNames)
      (RegExp('\\b(?:$pattern)\\b', caseSensitive: false), name),
  ];

  /// App receipts print plan names ("Uber One"); always use the plain name.
  static const Set<String> _appBrands = {
    'Uber', 'Uber Eats', 'DiDi', 'DiDi Food', 'Cabify', 'Rappi', 'Lyft',
    'Airbnb', 'inDrive', 'PedidosYa', 'Deliveroo',
  };

  /// Short or everyday words that are a brand only where the name goes, at
  /// the start of one of the top rows ("SHELL", "ADO", "VIPS REFORMA",
  /// "TARGET"), never inside an item or an address ("HARD SHELL TACO", "1
  /// LIVERPOOL STREET", "COMBO UNO").
  static const List<(String, String)> _headerBrands = [
    ('shell', 'Shell'), ('puma', 'Puma'), ('uno', 'Uno'), ('bp', 'BP'), //
    ('mobil', 'Mobil'), ('gulf', 'Gulf'), ('ado', 'ADO'), ('etn', 'ETN'),
    ('vips', 'Vips'), ('toks', 'Toks'), ("chili's", "Chili's"),
    ('chilis', "Chili's"), ('ihop', 'IHOP'), ('subway', 'Subway'),
    ('chipotle', 'Chipotle'), ('sushi roll', 'Sushi Roll'),
    ('los cebollines', 'Los Cebollines'), ('san martin', 'San Martin'),
    ('liverpool', 'Liverpool'), ('suburbia', 'Suburbia'), ('sears', 'Sears'),
    ('target', 'Target'), ('pret', 'Pret'), ('boots', 'Boots'), ('cvs', 'CVS'),
    ('heb', 'H-E-B'), ('h-e-b', 'H-E-B'), ('paiz', 'Paiz'), ('asda', 'Asda'),
    ('aldi', 'Aldi'), ('lidl', 'Lidl'), ('itsu', 'Itsu'), ('avis', 'Avis'),
    ('sixt', 'Sixt'), ('zara', 'Zara'),
  ];

  /// "0XX0", "BURGER K1NG", "P0LLO CAMPER0": digits standing inside a word
  /// where their look-alike letters belong. For matching names only.
  static String _lettersForDigits(String text) => text.replaceAllMapped(
        RegExp(r'(?<=[A-Za-z])[0158](?=[A-Za-z])|'
            r'(?<![\w.,/\-])[0158](?=[A-Za-z]{2})|'
            r'(?<=[A-Za-z]{2})[0158](?![\w.,/\-])'),
        (m) => const {'0': 'O', '1': 'I', '5': 'S', '8': 'B'}[m[0]!]!,
      );

  static (RegExp, String)? _knownBrand(List<String> rows) {
    final text = _lettersForDigits(rows.join('\n'));
    // The brand printed nearest the top is the shop; one further down is a
    // partner, a card or an advert.
    (RegExp, String)? found;
    var at = text.length;
    for (final brand in _brands) {
      final match = brand.$1.firstMatch(text);
      if (match == null) continue;
      if (_appBrands.contains(brand.$2)) return brand;
      if (match.start < at) {
        at = match.start;
        found = brand;
      }
    }
    final header = _headerRows(rows).toSet();
    var start = 0;
    for (var i = 0; i < rows.length && start < at; i++) {
      final brand = header.contains(i) ? _headerBrand(rows[i]) : null;
      if (brand != null) return brand;
      start += rows[i].length + 1;
    }
    if (found != null) return found;
    // A long brand name read with a letter or two wrong ("starbLICks",
    // "stabckS"). Short names are left out: too easy to match by chance.
    // Single words, and two or three words together for names of several
    // ("COSTA COFEE" -> "costacofee").
    final tokens = [
      for (final line in text.split('\n'))
        [for (final m in RegExp('[A-Za-z]+').allMatches(line)) m[0]!.toLowerCase()],
    ];
    final words = [
      for (final line in tokens) ...[
        for (final t in line)
          if (t.length >= 6) t,
        for (var k = 0; k + 1 < line.length; k++)
          if (line[k].length >= 3 && line[k + 1].length >= 3)
            line[k] + line[k + 1],
        for (var k = 0; k + 2 < line.length; k++)
          if (line[k].length >= 3 && line[k + 2].length >= 3)
            line[k] + line[k + 1] + line[k + 2],
      ],
    ];
    for (final (word, name) in _fuzzyBrands) {
      // Two wrong letters in a long name, one in a shorter one.
      final edits = word.length >= 8 ? 2 : 1;
      for (final w in words) {
        if ((w.length - word.length).abs() <= edits &&
            _editDistance(w, word) <= edits) {
          return (RegExp(RegExp.escape(name), caseSensitive: false), name);
        }
      }
    }
    return null;
  }

  /// The [_headerBrands] name a top row starts with, if the row is little
  /// more than that name ("ADO", "VIPS REFORMA", "UNO GUATEMALA, S.A.").
  static (RegExp, String)? _headerBrand(String raw) {
    final cleaned = _cleanCandidate(raw);
    if (_notAName(raw, cleaned)) return null;
    if (!_legalSuffix.hasMatch(cleaned) && _isAddress(cleaned)) return null;
    final row = TextNormaliser.stripDiacritics(_lettersForDigits(cleaned))
        .toLowerCase()
        .replaceAll('’', "'");
    for (final (word, name) in _headerBrands) {
      if (!row.startsWith(word)) continue;
      final rest = row.substring(word.length);
      if (RegExp('^[a-z0-9]').hasMatch(rest)) continue; // "SHELLFISH"
      final more = RegExp('[a-z0-9]+').allMatches(
        rest.replaceAll(_legalSuffix, ''),
      );
      if (more.length > 2) continue;
      return (
        RegExp('\\b${RegExp.escape(word)}(?![a-z0-9])', caseSensitive: false),
        name,
      );
    }
    return null;
  }

  static const List<(String, String)> _fuzzyBrands = [
    ('starbucks', 'Starbucks'),
    ('costacoffee', 'Costa Coffee'),
    ('sanborns', 'Sanborns'),
    ('marriott', 'Marriott'),
    ('aeromexico', 'Aeroméxico'),
    ('mcdonalds', "McDonald's"),
    ('burgerking', 'Burger King'),
    ('pollocampero', 'Pollo Campero'),
    ('littlecaesars', 'Little Caesars'),
    ('krispykreme', 'Krispy Kreme'),
    ('dominospizza', "Domino's"),
    ('cielitoquerido', 'Cielito Querido'),
    ('puntadelcielo', 'Punta del Cielo'),
    ('pretamanger', 'Pret A Manger'),
    ('walmart', 'Walmart'),
    ('chedraui', 'Chedraui'),
    ('bodegaaurrera', 'Bodega Aurrera'),
    ('pricesmart', 'PriceSmart'),
    ('walgreens', 'Walgreens'),
    ('farmaciasguadalajara', 'Farmacias Guadalajara'),
    ('farmaciasdelahorro', 'Farmacias del Ahorro'),
    ('farmaciassimilares', 'Farmacias Similares'),
    ('farmatodo', 'Farmatodo'),
    ('cinepolis', 'Cinépolis'),
    ('cinemex', 'Cinemex'),
    ('avianca', 'Avianca'),
    ('britishairways', 'British Airways'),
    ('vivaaerobus', 'Viva Aerobus'),
    ('holidayinn', 'Holiday Inn'),
    ('sheraton', 'Sheraton'),
    ('radisson', 'Radisson'),
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
    final (guess, legal) = _layoutMerchant(rows, heights, pieces);
    final brand = _knownBrand(rows);
    // Nothing near the top names the place: its own web or e-mail address
    // further down may.
    if (brand == null) return guess ?? _domainName(rows);
    if (guess == null || legal || _appBrands.contains(brand.$2)) {
      return brand.$2;
    }
    // Keep a fuller printed name ("Starbucks Coffee", "Vips Reforma") when
    // it is the brand, with the brand spelt its own way ("OXXO", not
    // "Oxxo"). A company name around it ("CADENA COMERCIAL OXXO SA DE CV")
    // is not kept.
    final match = brand.$1.firstMatch(_lettersForDigits(guess));
    if (match == null) return brand.$2;
    final before = TextNormaliser.smartTitleCase(guess.substring(0, match.start));
    final after = TextNormaliser.smartTitleCase(guess.substring(match.end));
    return [
      if (before.isNotEmpty) before,
      brand.$2,
      if (after.isNotEmpty) after,
    ].join(' ').replaceAll(RegExp(r"\s+(?=[/,.'])"), '');
  }

  /// Drops marks before the first word ("¡BIENVENIDOS!"), a leading Mexican
  /// RFC ("XXX010101AB1-DUFRY…") and a bank name printed beside the shop's
  /// on a card slip ("Bancamiga EJEMPLO 360").
  static String _cleanCandidate(String row) => row
      .replaceFirst(RegExp(r'^[^A-Za-z0-9À-ÿ(]+'), '')
      .replaceFirst(RegExp(r'^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\s*[-–]?\s*'), '')
      .replaceFirst(
        RegExp(r'^(banc\w*|banco|bank)\s+(?=\S)', caseSensitive: false),
        '',
      );

  /// The headings over the items ("CANT DESCRIPCION IMPORTE", "NOMBRE").
  static final RegExp _itemsHeading = RegExp(
    r'^\W*(nombre|cant\.?|cantidad|descripci[oó]n|producto|art[ií]culo|'
    r'concepto|qty|quantity|item|description|'
    // Portuguese: "# COD DESCRICAO QTD UN VL UNIT VL TOTAL".
    r'c[oó]d(?:igo)?\.?\s+descri\w+|descri[cç][aã]o|qtde?)\b',
    caseSensitive: false,
  );

  /// Whether a top row is something other than a name: a bank, a heading,
  /// a field, a document title, a tax regime, a request, an item.
  /// [raw] is the row as read, [row] the same after [_cleanCandidate].
  static bool _notAName(String raw, String row) =>
      _acquirer.hasMatch(raw.replaceFirst(RegExp(r'^[^A-Za-z0-9À-ÿ(]+'), '')) ||
      _merchantNoise.hasMatch(row) ||
      _greeting.hasMatch(row) ||
      _serviceRow.hasMatch(row) ||
      _branchRow.hasMatch(row) ||
      _fieldRow.hasMatch(row) ||
      _documentWord.hasMatch(row) ||
      _taxStatus.hasMatch(row) ||
      _request.hasMatch(row) ||
      _pricedRow.hasMatch(row) ||
      _maskedNumber.hasMatch(row) ||
      _bareOutlet.hasMatch(row) ||
      _loneSuffix.hasMatch(row) ||
      _headCount.hasMatch(row);

  /// "2 PASAJEROS", "3 ADULTOS", "4 PAX": how many people.
  static final RegExp _headCount = RegExp(
    r'^\W*\d{1,2}\s+(?:pasajeros?|pax|personas?|adultos?|ni[ñn]os?|menores|'
    r'passengers?|guests?|adults?|maletas?)\b',
    caseSensitive: false,
  );

  /// The outlet of a hotel or the kind of place, with no name of its own:
  /// "RESTAURANTE", "BAR", "LOBBY BAR", "ROOM SERVICE".
  static final RegExp _bareOutlet = RegExp(
    r'^\W*(?:restaurante?|bar|lobby\s+bar|pool\s+bar|snack\s+bar|'
    r'sports\s+bar|room\s+service|servicio\s+a\s+(?:la\s+)?habitaci[oó]n|'
    r'cafeter[ií]a|alimentos\s+y\s+bebidas)\W*$',
    caseSensitive: false,
  );

  /// The end of a company name printed on a row of its own: "SA DE CV",
  /// "S.A. DE C.V.", "S DE RL DE CV", "LTDA".
  static final RegExp _loneSuffix = RegExp(
    r'^\W*(?:s\.?\s?a\.?(?:\s?p\.?\s?i\.?)?(?:\s?b\.?)?\s+de\s+c\.?\s?v\.?|'
    r's\.?\s+de\s+r\.?\s?l\.?(?:\s+de\s+c\.?\s?v\.?)?|s\.?\s?a\.?\s?s\.?|'
    r's\.\s?a\.|ltda\.?|inc\.?|llc)\W*$',
    caseSensitive: false,
  );

  /// A label whose value, on the next row, is where to or for whom:
  /// "DESTINO:", "CLIENTE:", "Bill to:". Labels that say who sells
  /// ("Emisor:", "Vendido por:", "Sold by:") are not among them.
  static final RegExp _bareLabel = RegExp(
    r'^\W*(?:destino|origen|cliente|receptor|hu[eé]sped|pasajeros?|'
    r'nombre(?:\s+del?\s+cliente)?|facturar\s+a|entregar\s+(?:a|en)|'
    r'direcci[oó]n(?:\s+de\s+entrega)?|bill(?:ed)?\s+to|ship(?:ped)?\s+to|'
    r'sold\s+to|deliver(?:ed)?\s+to|guest|customer|destination|to)\s*:\s*$',
    caseSensitive: false,
  );

  /// More parts of an address, beside a number or a comma ("ZONA 10",
  /// "LOCAL 23 PB", "KM 16.5", "PISO 2", "DIAGONAL 6 10-01").
  static final RegExp _placeWord = RegExp(
    r'\b(zona|local|loc|km|kil[oó]metro|edificio|edif|torre|nivel|piso|'
    r'manzana|mz|lote|interior|depto|dpto|apto|sector|barrio|urb|'
    r'urbanizaci[oó]n|fracc|fraccionamiento|residencial|suite|ste|floor|'
    r'unit|diagonal|transversal|carrera|cra|autopista|perif[eé]rico|'
    r'circuito|paseo|pasaje|callej[oó]n|prolongaci[oó]n|prol|street|road|'
    r'highway|hwy)\b',
    caseSensitive: false,
  );

  /// "1234 EXAMPLE ST", "10 Example Street": a house number, then a street.
  static final RegExp _streetNumber = RegExp(
    r'^#?\d{1,5}[A-Za-z]?\s.*\b(st|street|rd|road|ave|avenue|blvd|boulevard|'
    r'dr|drive|ln|lane|way|hwy|highway|pkwy|parkway|ct|court|pl|place|sq|'
    r'square|terrace|close|row|pike|trail|circle)\b',
    caseSensitive: false,
  );

  /// "HOUSTON, TX 77002" and "LONDON W1A 1AA": a US state and ZIP code, a
  /// UK postcode.
  static final RegExp _postcode = RegExp(
    r',\s*[A-Za-z]{2}\.?\s+\d{5}(-\d{4})?\b|\b[A-Z]{1,2}\d[A-Z\d]?\s\d[A-Z]{2}\b',
  );

  /// A state or department closing a "TOWN, STATE" row ("ZAPOPAN, JALISCO",
  /// "MERIDA, YUC.", "MIXCO, GUATEMALA", "CHACAO, MIRANDA").
  static final RegExp _regionTail = RegExp(
    r',\s*(aguascalientes|ags|baja\s+california(\s+sur)?|b\.?\s?c\.?(\s?s)?|'
    r'campeche|camp|chiapas|chis|chihuahua|chih|coahuila|coah|colima|'
    r'durango|dgo|guanajuato|gto|guerrero|gro|hidalgo|hgo|jalisco|jal|'
    r'm[eé]xico|m[eé]x|edo\.?\s*(de\s*)?m[eé]x(ico)?|michoac[aá]n|mich|'
    r'morelos|mor|nayarit|nay|nuevo\s+le[oó]n|n\.?\s?l|oaxaca|oax|puebla|pue|'
    r'quer[eé]taro|qro|quintana\s+roo|q\.?\s?roo|san\s+luis\s+potos[ií]|'
    r's\.?\s?l\.?\s?p|sinaloa|sin|sonora|son|tabasco|tab|tamaulipas|tamps|'
    r'tlaxcala|tlax|veracruz|ver|yucat[aá]n|yuc|zacatecas|zac|cdmx|d\.?\s?f|'
    r'sacatep[eé]quez|quetzaltenango|escuintla|chimaltenango|pet[eé]n|'
    r'alta\s+verapaz|izabal|huehuetenango|la\s+libertad|santa\s+ana|'
    r'san\s+miguel|sonsonate|cundinamarca|antioquia|valle\s+del\s+cauca|'
    r'atl[aá]ntico|miranda|zulia|carabobo|aragua|lara|distrito\s+capital|'
    r'nueva\s+esparta|anzo[aá]tegui)\.?\s*$',
    caseSensitive: false,
  );

  /// "HOTEL EJEMPLO CANCUN", "CAFE COLOMBIA", "TACOS MEXICO": a business
  /// called after its town or country. With no number or comma on the row
  /// it is a name, not an address. Only words that say what kind of place
  /// it is: "TIENDA GUADALAJARA CENTRO" is a branch, "GRUPO ... DE MEXICO"
  /// a company, "CLUB DE GOLF MEXICO" a neighbourhood.
  static final RegExp _businessStart = RegExp(
    r'^\W*(?:hotel|hostal|posada|motel|caf[eé]|cafeter[ií]a|restaurante?|'
    r'cantina|tacos|taquer[ií]a|pizzer[ií]a|pizza|farmacia|panader[ií]a|'
    r'pasteler[ií]a|mariscos|tortas|sushi|burger|museo)\s+\S',
    caseSensitive: false,
  );


  /// Address lines name places and streets ("CHACAO CARACAS (CHACAO)
  /// MIRANDA", "C.EJEMPLO, L.1, COL.CENTRO", "ZONA 10", "1234 EXAMPLE ST",
  /// "HOUSTON, TX 77002", "ZAPOPAN, JALISCO").
  ///
  /// A row that only names a town or country is spared when it reads as a
  /// business called after the place ("HOTEL EJEMPLO CANCUN") and no name
  /// stands above it ([named]), or when the kind of place is printed on the
  /// row next to it ("RESTAURANTE" / "LA EJEMPLO DE OAXACA", [byOutlet]).
  static bool _isAddress(
    String row, {
    bool named = true,
    bool byOutlet = false,
  }) {
    final spared = !RegExp(r'[\d,]').hasMatch(row) &&
        (byOutlet || (named && _businessStart.hasMatch(row)));
    return (Countries.detectInText(row) != null && !spared) ||
        ((_addressRow.hasMatch(row) || _placeWord.hasMatch(row)) &&
            RegExp(r'[\d,]').hasMatch(row)) ||
        _streetNumber.hasMatch(row) ||
        _postcode.hasMatch(row) ||
        _regionTail.hasMatch(row);
  }

  /// The rows the name can be on: the top eight with words in them (rules
  /// ("=====") and stray marks from a QR code do not use up the window),
  /// and never under the items' column headings, a total, or the second
  /// row that ends in a price.
  static List<int> _headerRows(List<String> rows) {
    final top = <int>[];
    var priced = 0;
    for (var i = 0; i < rows.length && i < 14 && top.length < 8; i++) {
      if (!_merchantLabel.hasMatch(rows[i])) {
        if (_itemsHeading.hasMatch(rows[i]) || _totalRow.hasMatch(rows[i])) {
          break;
        }
        if (_pricedRow.hasMatch(rows[i]) && ++priced == 2) break;
      }
      if (TextNormaliser.letterCount(rows[i]) >= 3) top.add(i);
    }
    return top;
  }

  /// The name as the top rows give it, and whether it is only the
  /// registered company ("GRUPO EJEMPLO ALIMENTOS, SA DE CV").
  (String?, bool) _layoutMerchant(
    List<String> rows,
    List<double> heights,
    List<List<(String, double)>> pieces,
  ) {
    String? best;
    var bestScore = 0.0;
    String? plain;
    var plainScore = 0.0;
    // Whether a name has already been found above the row at hand.
    var seen = false;
    final top = _headerRows(rows);
    var maxHeight = 0.0;
    for (final i in top) {
      if (heights[i] > maxHeight) maxHeight = heights[i];
    }
    // Each row, and each piece of a row that OCR joined from several lines.
    // (row index, place among the top rows, text, height)
    final candidates = <(int, int, String, double)>[
      for (var n = 0; n < top.length; n++) ...[
        (top[n], n, rows[top[n]], heights[top[n]]),
        if (pieces[top[n]].length > 1)
          for (final (t, h) in pieces[top[n]]) (top[n], n, t, h),
      ],
    ];
    for (final (i, place, text, height) in candidates) {
      // "COMERCIO: TACOS EJEMPLO": the row says it is the name.
      final named = _merchantLabel.firstMatch(text);
      final row = named != null ? named[1]!.trim() : _cleanCandidate(text);
      final letters = TextNormaliser.letterCount(row);
      if (letters < 3) continue;
      final digits = RegExp(r'\d').allMatches(row).length;
      if (digits > letters) continue;
      if (named == null && _notAName(text, row)) continue;
      // A word that mixes digits and letters ("1OMeAPERTURA", "MYT015") is
      // a code or OCR noise, not a shop name.
      if (row.split(' ').any((w) =>
          w.length >= 4 &&
          RegExp(r'\d').hasMatch(w) &&
          RegExp('[A-Za-z]{2}').hasMatch(w))) {
        continue;
      }
      final byOutlet = (i > 0 &&
              _bareOutlet.hasMatch(_cleanCandidate(rows[i - 1]))) ||
          (i + 1 < rows.length &&
              _bareOutlet.hasMatch(_cleanCandidate(rows[i + 1])));
      // Only while no name stands above: under "INVERSIONES EJEMPLO, S.A."
      // / "RESTAURANTE" the next row is the town.
      if (!_legalSuffix.hasMatch(row) &&
          _isAddress(row, named: !seen, byOutlet: byOutlet && !seen)) {
        continue;
      }
      if (i > 0 &&
          _greeting.hasMatch(rows[i - 1]) &&
          rows[i - 1].trimRight().endsWith(',')) {
        continue; // the customer's name, not the shop's
      }
      // The value under a bare label ("DESTINO:" / "HOTEL EJEMPLO CANCUN",
      // "CLIENTE:" / a company) is where to or for whom, not the shop.
      if (named == null && i > 0 && _bareLabel.hasMatch(rows[i - 1])) {
        continue;
      }
      if (_datesIn(row).isNotEmpty) continue;
      seen = true;

      var score = named != null ? 1.5 : 1.0 - place * 0.08;
      // Big print helps a little, but a heading ("PRECUENTA") is often the
      // biggest text; the name is mostly decided by being near the top.
      if (maxHeight > 0) score *= 0.7 + 0.3 * (height / maxHeight);
      // A company name split over two lines ("SANTA CLARA MERCANTIL DE" /
      // "PACHUCA S. DE R.L DE C.V"): the first half is the legal name too.
      final dangling =
          RegExp(r'\s(de|del|y|e|&)$', caseSensitive: false).hasMatch(row);
      final legal = _legalSuffix.hasMatch(row) ||
          (dangling &&
              i + 1 < rows.length &&
              _legalSuffix.hasMatch(rows[i + 1].trim()));
      if (legal) score *= 0.9;
      if (dangling && !legal) score *= 0.6;
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
    var legal = best != null;
    if (plain != null && plainScore >= bestScore * 0.55) {
      best = plain;
      legal = false;
    } else if (plain != null && best == null) {
      best = plain;
    }
    if (best == null) return (null, false);
    // Stylised capitals are sometimes read twice: "HHotel".
    var cleaned = best
        .replaceAllMapped(RegExp(r'\b([A-Z])\1(?=[a-z])'), (m) => m[1]!)
        .replaceAll(_legalSuffix, '');
    cleaned = cleaned.replaceAll(
      RegExp(r'^[^A-Za-z0-9À-ÿ]+|[^A-Za-z0-9À-ÿ)]+$'),
      '',
    );
    cleaned = TextNormaliser.smartTitleCase(cleaned);
    return cleaned.isEmpty ? (null, false) : (cleaned, legal);
  }

  /// A web or e-mail address: "www.cafe-ejemplo.com.mx",
  /// "facturas@cafe-ejemplo.com.mx", "https://cafe-ejemplo.com/factura".
  static final RegExp _webAddress = RegExp(
    r'(?:[\w.+\-]+@|https?://|www\.)((?:[a-z0-9\-]+\.)+[a-z]{2,})',
    caseSensitive: false,
  );

  /// The parts of an address that are not the owner's name.
  static const Set<String> _domainEndings = {
    'www', 'com', 'net', 'org', 'edu', 'gob', 'gov', 'info', 'biz', 'app', //
    'shop', 'store', 'rest', 'io', 'mx', 'gt', 'sv', 'hn', 'ni', 'cr', 'pa',
    'co', 've', 'pe', 'cl', 'ar', 'br', 'ec', 'bo', 'uy', 'py', 'do', 'es',
    'pt', 'uk', 'us', 'ca', 'eu',
  };

  /// Sites that belong to someone other than the shop: payment and card
  /// companies, invoicing and tax portals, surveys, mail and social
  /// networks, link shorteners, till software.
  static final RegExp _foreignSite = RegExp(
    r'factur|cfdi|invoice|ticket|encuesta|survey|opinion|feedback|pago|'
    r'payment|bank|banc|soft|sistema|system|mail|facebook|instagram|twitter|'
    r'tiktok|whatsapp|youtube|google|hacienda|seniat|infile|digifact|'
    r'megaprint|edicom|contpaq|paypal|getnet|zettle|sumup|netpay|openpay|'
    r'conekta|stripe|billpocket|linktr|'
    r'^(sat|gob|gov|dian|mh|pos|app|web|live|msn|aol|outlook|yahoo|icloud|'
    r'prodigy|proton|clip|visa|amex|mastercard|square|toast|bit|qr|fb|goo|'
    r'wa|t|x)$',
  );

  /// A row that credits the till's software or a certifier ("Sistema:
  /// www.example-pos.com", "Certificador: INFILE").
  static final RegExp _creditRow = RegExp(
    r'sistema|software|desarrollado|powered|certificador|proveedor',
    caseSensitive: false,
  );

  /// The kind of business a web address often starts with, to put the
  /// space back: "cafeejemplo" -> "cafe ejemplo".
  static final RegExp _businessPrefix = RegExp(
    r'^(cafeteria|cafe|restaurante|restaurant|hotel|hostal|tacos|taqueria|'
    r'pizzeria|pizza|farmacia|panaderia|pasteleria|mariscos|tortas|sushi|'
    r'burger|grupo)(?=[a-z]{4,}$)',
  );

  /// When nothing near the top names the place: the one web or e-mail
  /// address on the receipt that is the shop's own ("www.cafe-ejemplo.com.mx"
  /// -> "Cafe Ejemplo"). Null when there is none, or more than one.
  static String? _domainName(List<String> rows) {
    final names = <String>{};
    for (final raw in rows) {
      if (_creditRow.hasMatch(raw)) continue;
      // "www.cafe-ejemplo.com. mx": a space OCR put after a dot.
      final row = raw.replaceAllMapped(
        RegExp(r'\.\s(?=(com|mx|gt|sv|co|net|org|uk)\b)', caseSensitive: false),
        (m) => '.',
      );
      for (final m in _webAddress.allMatches(row)) {
        final labels = m[1]!.toLowerCase().split('.')
          ..removeWhere(_domainEndings.contains);
        if (labels.isEmpty) continue;
        if (labels.any(_foreignSite.hasMatch)) continue;
        final name = labels.last;
        if (RegExp('[a-z]').allMatches(name).length < 4) continue;
        names.add(name);
      }
    }
    if (names.length != 1) return null;
    final words = names.single
        .replaceFirstMapped(_businessPrefix, (m) => '${m[1]} ')
        .replaceAll(RegExp(r'[\-_]+'), ' ')
        .toUpperCase();
    return TextNormaliser.smartTitleCase(words);
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

  /// "28 JUL 2026", "4 de noviembre de 2026", "23 Nov'26", "23rd November
  /// 2026", "23 N0V 2026" (a zero read for the O). The year must not be the
  /// start of a time or a price ("26 MAR 14:42", "1 MARUCHAN 18.50").
  /// Groups: day, "de", month, what separates month and year, "de", year.
  static final RegExp _dayMonthName = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-/.]*(de\s+)?([A-Za-zÁÉÍÓÚáéíóú0]{3,10})\.?'
    r"([\s\-/.,'’`´]*)(del?\s+)?(\d{4}|\d{2})\b"
    r'(?![:.]\d)(?!,\d(?!\d?[:.]\d{2}))',
    caseSensitive: false,
  );

  /// "NOV 23, 2026", "November 23rd, 2026", "Noviembre 23 de 2026",
  /// "NOV-23-2026": the month's name first, as US-made tills print it.
  /// Groups: month, the day (one of three), year.
  static final RegExp _monthNameDay = RegExp(
    r'\b([A-Za-z]{3,10})\.?(?:\s+(\d{1,2})(?:st|nd|rd|th)?'
    r'(?:\s*,\s*|\s+del?\s+|\s+)|-(\d{1,2})-|/(\d{1,2})/)(\d{4})\b'
    r'(?![:.]\d)(?!,\d(?!\d?[:.]\d{2}))',
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
  /// Also the day it was paid ("Pagado el 15 nov 2026"), which on an
  /// e-mail ticket stands beside the day of the service.
  static final RegExp _dateKeyword = RegExp(
    r'fecha|date|emisi[oó]n|emitido|pagado|pagaste|\bpaid\b|comprado|'
    r'purchased|cobrado|charged',
    caseSensitive: false,
  );

  /// Dates that are on the receipt but are not the day of purchase: valid
  /// until, tax-authority limits and resolutions, delivery, date of birth,
  /// member since, the day of a journey.
  static final RegExp _otherDate = RegExp(
    r'vigencia|vigente|v[aá]lid[oa]|\bvalid\b|vence|vencimiento|\bvto\b|'
    r'caduc|expir|l[ií]mite|nacimiento|\bbirth|\bdob\b|resoluci[oó]n|'
    r'\bres\.?\s*(dian|no\b|n[uú]m|n[°º])|rango\s*autorizado|numeraci[oó]n|'
    r'fecha\s*(de\s*)?autorizaci[oó]n|\bhasta\b|\buntil\b|\bdesde\b|'
    r'\bsince\b|\bentrega\b|best\s*before|use\s*by|pr[oó]xim[oa]|'
    r'\bdeliver(?:y|ed)\b|\bshipp?(?:ed|ing)\b|\bestimated\b|\barriv(?:al|es|ing)\b|'
    r'fecha\s*(del?\s*)?(viaje|vuelo)|(travel|flight)\s*date',
    caseSensitive: false,
  );

  /// The end of a stay or a visit: "Salida: 23/11/2026", "Check-out",
  /// "Departure". The bill is paid on that day.
  static final RegExp _departureWord = RegExp(
    r'check\s*-?\s*out|\bsalida\b|\bdeparture\b|\begreso\b',
    caseSensitive: false,
  );

  /// The start of a stay or a visit: "Llegada: 20/11/2026", "Check-in",
  /// "Arrival", a car park's "ENTRADA".
  static final RegExp _arrivalWord = RegExp(
    r'check\s*-?\s*in\b|\bllegada\b|\barrival\b|\bentrada\b|\bingreso\b',
    caseSensitive: false,
  );

  /// "Fecha de impresion", "IMPRESO": when the paper was printed, which is
  /// the purchase only if no other date says otherwise.
  static final RegExp _printedWord = RegExp(
    r'impresi[oó]n|impreso|reimpres|\bprinted\b|print\s*date',
    caseSensitive: false,
  );

  /// A row that announces another kind of date and leaves it for the next
  /// row: "... RESOLUCION No. 123 DE FECHA" / "12/03/2019".
  static final RegExp _danglingLabel =
      RegExp(r'\b(de|del|fecha|el|al|hasta|desde)\s*:?\s*$', caseSensitive: false);

  /// "DE FECHA 12/03/2019", "DEL 2026-02-10": a row that carries on from
  /// the one before.
  static final RegExp _continuedDate =
      RegExp(r'^\W*(de\s+fecha|del?\s+\d)', caseSensitive: false);

  /// A date-shaped run with letters where digits belong: "28/O7/2O26".
  static final RegExp _noisyDate = RegExp(
    r'(?<![A-Za-z0-9])([0-9OoQDIl|SBZ]{1,2})\s?([-/.])\s?'
    r'([0-9OoQDIl|SBZ]{1,2})\s?\2\s?([0-9OoQDIl|SBZ]{4}|[0-9OoQDIl|SBZ]{2})'
    r'(?![A-Za-z0-9])',
  );

  /// The same with the year first: "2O26-11-23".
  static final RegExp _noisyIsoDate = RegExp(
    r'(?<![A-Za-z0-9])([2Z][0OoQD][0-9OoQDIl|SBZ]{2})([-/.])'
    r'([0-9OoQDIl|SBZ]{1,2})\2([0-9OoQDIl|SBZ]{1,2})(?![A-Za-z0-9])',
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

  /// "16-1 1-2026": a space OCR put inside the month.
  static final RegExp _spaceInDate =
      RegExp(r'(?<=\b\d{1,2}[-/.]\d)\s(?=\d[-/.]\d{2,4}\b)');

  /// "23/11/20 26": a space OCR put inside the year. Not before a time or
  /// a price ("23/11/20 09:02").
  static final RegExp _spaceInYear = RegExp(
    r'(?<=\d\s?[-/.]\s?\d{1,2}\s?[-/.]\s?20)\s(?=\d{2}(?![\d:.,]))',
  );

  /// "23|11|2026", "23I11I2026": the slashes read as bars.
  static final RegExp _barredDate = RegExp(
    r'(?<![\w|])(\d{1,2})\s?([|Il])\s?(\d{1,2})\s?\2\s?(20\d{2})(?!\d)',
  );

  /// "23/NOV/2O26": the year after a month's name, a zero read as an O.
  static final RegExp _noisyYear = RegExp(
    r'(?<=[A-Za-z0]{3}\.?[\s\-/.,]{1,2})2[Oo0][0-9Oo]{2}(?![A-Za-z0-9])',
  );

  /// "Nov16'26", "NOV 16 '26": month, day and a two-digit year after an
  /// apostrophe, as some tills print it.
  static final RegExp _monthDayShortYear = RegExp(
    r"(?<![A-Za-z])([A-Za-z]{3,9})\.?\s?(\d{1,2})\s?['’`´]\s?(\d{2})(?!\d)",
  );

  /// "NOV 23, 26 09:02": the same after a comma, as card terminals print
  /// it. Only at the end of the row or before the time.
  static final RegExp _monthDayCommaYear = RegExp(
    r'(?<![A-Za-z])([A-Za-z]{3,10})\.?\s(\d{1,2}),\s?(\d{2})'
    r'(?=\s*$|\s+\d{1,2}:\d{2})',
  );

  /// Undoes what OCR does to a printed date: stray spaces, bars for
  /// slashes, and look-alike letters for digits, but only inside something
  /// already shaped like a date and mostly made of digits.
  static String _repairDates(String row) {
    var text = row
        .replaceAll(_spaceInDate, '')
        .replaceAll(_spaceInYear, '')
        .replaceAllMapped(_barredDate, (m) => '${m[1]}/${m[3]}/${m[4]}')
        .replaceAllMapped(
          _noisyYear,
          (m) => m[0]!.replaceAll(RegExp('[Oo]'), '0'),
        );
    for (final pattern in [_noisyDate, _noisyIsoDate]) {
      text = text.replaceAllMapped(pattern, (m) {
        final groups = [m[1]!, m[3]!, m[4]!];
        if (groups.any((g) => !RegExp(r'\d').hasMatch(g))) return m[0]!;
        final found = m[0]!;
        if (!RegExp(r'[A-Za-z|]').hasMatch(found)) return found;
        final buffer = StringBuffer();
        for (final rune in found.runes) {
          final char = String.fromCharCode(rune);
          buffer.write(_digitLookalikes[char] ?? char);
        }
        return buffer.toString();
      });
    }
    return text;
  }

  /// The purchase date and whether it needs checking. A labelled date
  /// ("FECHA 28/07/2026") wins; then a plain one; then a day found inside a
  /// ticket number; then the end or start of a stay; last, a date that is
  /// labelled as something else.
  (DateTime?, bool) _date(List<String> rawRows) {
    final now = _clock();
    final latest = DateTime(now.year, now.month, now.day + 1);
    final earliest = DateTime(2010);
    bool inRange(DateTime d) => !d.isBefore(earliest) && !d.isAfter(latest);
    final yearAgo = DateTime(now.year - 1, now.month, now.day);

    final rows = [for (final raw in rawRows) _repairDates(raw)];
    final read = [for (final row in rows) _readings(row)];
    final printedOrder = _printedOrder(read, DateTime(now.year + 2));
    final monthFirst = printedOrder ?? monthFirstDates;
    // Dates whose day and month were told apart only by which is recent.
    final guessed = <DateTime>{};
    final lately = DateTime(now.year, now.month, now.day - 45);
    final longAgo = DateTime(now.year, now.month, now.day - 90);

    // One reading of a date in figures, or none. "11/12/2026" scanned on 23
    // November cannot be 11 December: it is 12 November, printed month
    // first by a US-made till. "11/05/26" is far more likely 5 November
    // than a receipt kept since May. Both are guesses, to be checked.
    DateTime? settle((int, DateTime?, DateTime?, DateTime?) reading) {
      final (_, dayFirst, monthFirstDate, fixed) = reading;
      if (fixed != null) return inRange(fixed) ? fixed : null;
      final usual = monthFirst ? monthFirstDate : dayFirst;
      final swapped = monthFirst ? dayFirst : monthFirstDate;
      if (usual == null) {
        return swapped != null && inRange(swapped) ? swapped : null;
      }
      final recentSwap = printedOrder == null &&
          swapped != null &&
          inRange(swapped) &&
          !swapped.isBefore(lately);
      if (!inRange(usual)) {
        if (!recentSwap) return null;
        guessed.add(swapped);
        return swapped;
      }
      if (recentSwap && !monthFirstDates && usual.isBefore(longAgo)) {
        guessed.add(swapped);
        return swapped;
      }
      return usual;
    }

    String? kindOf(String words) {
      if (_otherDate.hasMatch(words)) return 'other';
      if (_departureWord.hasMatch(words)) return 'departure';
      if (_arrivalWord.hasMatch(words)) return 'arrival';
      if (_printedWord.hasMatch(words)) return 'printed';
      if (_dateKeyword.hasMatch(words)) return 'label';
      return null;
    }

    final labelled = <DateTime>[];
    final plain = <DateTime>[];
    final other = <DateTime>[];
    final arrivals = <DateTime>[];
    final departures = <DateTime>[];
    final compact = <DateTime>[];
    // (first number, year) of dates whose middle was unreadable.
    final partials = <(int, int)>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final found = <(int, DateTime)>[
        for (final reading in read[i])
          if (settle(reading) case final date?) (reading.$1, date),
      ];
      if (found.isNotEmpty) {
        // Each date is what the words before it say: "FECHA: 12/11/2026
        // VENCE: 12/12/2026", "Llegada: 20/11/2026 Salida: 23/11/2026". A
        // date with no words of its own ("DEL 01/11/2026 AL 30/11/2026") is
        // the same kind as the one before it.
        final carriedOn = i > 0 &&
            read[i - 1].isEmpty &&
            kindOf(rows[i - 1]) == 'other' &&
            (_danglingLabel.hasMatch(rows[i - 1]) ||
                _continuedDate.hasMatch(row) ||
                // "Fecha 2026-02-10 Vigencia 24 meses" under "Autorizacion
                // numeracion de facturacion ...": the row itself goes on
                // to say what its date is.
                _otherDate.hasMatch(row.substring(found.last.$1)));
        // A label after its date ("23/11/2026 :FECHA") still labels it,
        // unless it belongs to another kind of date further on.
        final rest = row.substring(found.first.$1);
        final others = [_otherDate, _departureWord, _arrivalWord, _printedWord]
            .map((p) => p.firstMatch(rest)?.start ?? rest.length)
            .reduce((a, b) => a < b ? a : b);
        var kind = carriedOn
            ? 'other'
            : _dateKeyword.hasMatch(rest.substring(0, others))
                ? 'label'
                : null;
        var from = 0;
        for (final (at, date) in found) {
          final words = kindOf(row.substring(from, at));
          if (words != null && !(carriedOn && from == 0 && words == 'label')) {
            kind = words;
          }
          from = at;
          switch (kind) {
            case 'other':
              other.add(date);
            case 'departure':
              departures.add(date);
            case 'arrival':
              arrivals.add(date);
            case 'label':
              labelled.add(date);
            default:
              plain.add(date);
          }
        }
        continue;
      }
      final partial = _partialDate.firstMatch(row);
      if (partial != null) {
        partials.add((int.parse(partial[1]!), int.parse(partial[2]!)));
      }
      if (_phoneRow.hasMatch(row)) continue;
      // "2O26O728": zeros read as the letter O inside a run of digits.
      final digits = row.replaceAll(RegExp(r'(?<=\d)[Oo]|[Oo](?=\d)'), '0');
      for (final m in _compactDate.allMatches(digits)) {
        final date =
            _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
        if (date != null && inRange(date)) compact.add(date);
      }
    }

    // A date years old beside a recent one is not a misread year: it is a
    // resolution of the tax authority ("DE FECHA 12/03/2019"), a member
    // since, or a street number read as a year.
    bool recent(DateTime d) => !d.isBefore(yearAgo);
    if (labelled.any(recent) || plain.any(recent)) {
      other
        ..addAll(labelled.where((d) => !recent(d)))
        ..addAll(plain.where((d) => !recent(d)));
      labelled.removeWhere((d) => !recent(d));
      plain.removeWhere((d) => !recent(d));
    }

    final departure = departures.isEmpty ? null : departures.last;
    final DateTime? date;
    var doubtful = false;
    if (labelled.isNotEmpty) {
      date = labelled.first;
    } else if (departure != null && plain.contains(departure)) {
      // A stay with dated charges: the bill is the day of departure, which
      // is also the last day printed on its own.
      date = departure;
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
    } else if (departure != null) {
      date = departure;
      // In and out on different days: paid on the way out, most likely.
      doubtful = arrivals.any((d) => d != departure);
    } else if (arrivals.isNotEmpty) {
      date = arrivals.first;
    } else if (other.isNotEmpty) {
      date = other.first;
      doubtful = true;
    } else {
      return (null, false);
    }
    if (guessed.contains(date)) doubtful = true;
    // An old unlabelled date (often a street name read as one) against a
    // recent day in the ticket number: the ticket number is the better
    // guess.
    if (labelled.isEmpty &&
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

  /// Whether this receipt prints its dates month first (true), day first
  /// (false), or does not show it (null). A date that reads only one way
  /// ("12/31/2026", "13/04/2026") shows it for the others; so does the same
  /// day printed with the month's name ("Nov05'26" beside "11/05/2026").
  static bool? _printedOrder(
    List<List<(int, DateTime?, DateTime?, DateTime?)>> read,
    DateTime latest,
  ) {
    bool sane(DateTime? d) =>
        d != null && d.year >= 2010 && !d.isAfter(latest);
    final all = [for (final row in read) ...row];
    final named = {
      for (final r in all)
        if (r.$4 != null) r.$4!,
    };
    var dayFirst = 0;
    var monthFirst = 0;
    for (final (_, day, month, fixed) in all) {
      if (fixed != null) continue;
      if (month == null || (named.contains(day) && !named.contains(month))) {
        if (sane(day)) dayFirst++;
      } else if (day == null || (named.contains(month) && !named.contains(day))) {
        if (sane(month)) monthFirst++;
      }
    }
    if (dayFirst > 0 && monthFirst == 0) return false;
    if (monthFirst > 0 && dayFirst == 0) return true;
    return null;
  }

  /// The dates on a row, read in the country's usual order.
  List<DateTime> _datesIn(String row) => [
        for (final (_, dayFirst, monthFirst, fixed) in _readings(row))
          fixed ??
              (monthFirstDates
                  ? (monthFirst ?? dayFirst)
                  : (dayFirst ?? monthFirst))!,
      ];

  /// Every date on a row, left to right: where it starts, and its reading
  /// with the day first, with the month first ("03/04/2026" has both), or
  /// the single reading of a date with the year first or a month's name.
  static List<(int, DateTime?, DateTime?, DateTime?)> _readings(String row) {
    final found = <(int, DateTime?, DateTime?, DateTime?)>[];
    void add(int at, DateTime? date) {
      if (date != null) found.add((at, null, null, date));
    }

    for (final m in _isoDate.allMatches(row)) {
      add(
        m.start,
        _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
      );
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
      final dayFirst = _validDate(year, b, a);
      final monthFirst = _validDate(year, a, b);
      if (a == b) {
        add(m.start, dayFirst);
      } else if (dayFirst != null || monthFirst != null) {
        found.add((m.start, dayFirst, monthFirst, null));
      }
    }
    if (!_addressRow.hasMatch(row) || _dateKeyword.hasMatch(row)) {
      for (final m in _dayMonthName.allMatches(row)) {
        final month = _monthFromName(m[3]!);
        if (month == null) continue;
        // "5 DE MAYO 12 CENTRO" is a street and its number: written out
        // with "de", a date has all four digits of its year, or says "de"
        // again ("5 de mayo del 26").
        if (m[2] != null &&
            m[6]!.length == 2 &&
            m[5] == null &&
            !RegExp("['’`´]").hasMatch(m[4]!)) {
          continue;
        }
        add(
          m.start,
          _validDate(_fullYear(int.parse(m[6]!)), month, int.parse(m[1]!)),
        );
      }
      for (final pattern in [_monthDayShortYear, _monthDayCommaYear]) {
        for (final m in pattern.allMatches(row)) {
          final month = _monthFromName(m[1]!);
          if (month == null) continue;
          add(
            m.start,
            _validDate(_fullYear(int.parse(m[3]!)), month, int.parse(m[2]!)),
          );
        }
      }
      for (final m in _monthNameDay.allMatches(row)) {
        final month = _monthFromName(m[1]!);
        if (month == null) continue;
        final day = int.parse((m[2] ?? m[3] ?? m[4])!);
        add(m.start, _validDate(int.parse(m[5]!), month, day));
      }
    }
    return found..sort((x, y) => x.$1.compareTo(y.$1));
  }

  static int? _monthFromName(String name) {
    final key = TextNormaliser.stripDiacritics(name)
        .toLowerCase()
        .replaceAll('0', 'o');
    if (key.length < 3) return null;
    if (!_monthNames.any((m) => m.startsWith(key))) return null;
    return _monthPrefixes[key.substring(0, 3)];
  }

  static int _fullYear(int year) => year < 100 ? 2000 + year : year;

  /// The day, or null when the calendar has no such day (31/02, month 13).
  static DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    return date.month == month && date.day == day ? date : null;
  }

  // -------------------------------------------------------------------- time

  /// "14:35", "02:35:10 p. m.", "9:02PM". May stand hard against a date or
  /// its "T" ("2026-11-23T09:02:11").
  static final RegExp _timePattern = RegExp(
    r'(?<![\d.,:])([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?(?!\d)'
    r'(?:\s*([ap]\.?\s?m\b\.?))?',
    caseSensitive: false,
  );
  static final RegExp _timeKeyword =
      RegExp(r'hora|time|fecha|date', caseSensitive: false);

  /// Opening hours and house rules, which print times that are not the
  /// purchase: "HORARIO: LUN A DOM 07:00 A 23:00", "Abierto de 7:00 a
  /// 23:00", "Check-out 12:00".
  static final RegExp _hoursRow = RegExp(
    r'horario|abierto|abrimos|\bopen\b|opening|\bhours\b|check\s*-?\s*(in|out)|'
    r'\d{1,2}:\d{2}\s*(hrs?\.?\s*)?(a|al|to|-|–)\s*(las\s*)?\d{1,2}:\d{2}',
    caseSensitive: false,
  );

  /// "28/07/202614:42": a time printed hard against the year.
  static final RegExp _timeAfterYear = RegExp(r'(?<=[-/.]\d{4})(?=\d{1,2}:\d{2})');

  String? _time(List<String> rows) {
    RegExpMatch? fallback;
    for (final raw in rows) {
      final row = raw.replaceAll(_timeAfterYear, ' ');
      final match = _timePattern.firstMatch(row);
      if (match == null) continue;
      final dated = _datesIn(row).isNotEmpty;
      if (_hoursRow.hasMatch(row) && !dated) continue;
      if (_timeKeyword.hasMatch(row) || dated) {
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
    // What was paid in the end, after a coupon: "Total pagado \$107.60".
    (
      RegExp(
        r'total\s*pagado|total\s*paid|total\s*cobrado|total\s*charged',
        caseSensitive: false,
      ),
      85,
    ),
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

  /// "TOTAL (IVA 16% INCLUIDO) $240.00": the percentage is a note that the
  /// tax is in the total, not a suggested tip or a tax row.
  static final RegExp _includedNote =
      RegExp(r'\binc(?:l\w*|\b)', caseSensitive: false);

  /// Money taken off under the subtotal: "DESCUENTO -229.70", "Promoción
  /// -MX\$151.80", "CUPON", "AHORRO".
  static final RegExp _offSubtotal = RegExp(
    r'^\W*(?:descuentos?|desc\.|dcto\.?|dscto\.?|promoci[oó]n|promo\b|ahorro|'
    r'cup[oó]n|bonificaci[oó]n|rebaja|discount|coupon|savings?)',
    caseSensitive: false,
  );

  /// A price for each hour, day or litre: "TARIFA: \$20.00 X HORA". Not
  /// what was paid.
  static final RegExp _rateRow = RegExp(
    r'\d\s*(?:x|por|per|/)\s*(?:hora|hr|hour|d[ií]a|day|fracci[oó]n|minuto|'
    // At the end of the row: "Precio total (MXN 945.00 por día) MXN
    // 2,835.00" is a total that also says the rate.
    r'min|km|litro|gal[oó]n)\b\W*$',
    caseSensitive: false,
  );

  /// Whether [row] cannot be the bill's total: a subtotal, or a row with a
  /// percentage (a tax, or a tip suggestion such as "15% $71.25 TOTAL
  /// $546.25") unless that percentage is only the tax-included note.
  bool _isNotTotal(String row) {
    if (_subtotalRow.hasMatch(row) || _rateRow.hasMatch(row)) return true;
    if (!_notTotal.hasMatch(row)) return false;
    return !(_taxRow.hasMatch(row) &&
        _includedNote.hasMatch(row) &&
        !_tipOnly.hasMatch(row) &&
        _decimalAmounts([row], 2).length == 1);
  }

  /// The total of one part of the bill, not the bill: "TOTAL AHORRO
  /// $324.60", "TOTAL DESCUENTOS", "TOTAL IVA 41.66", "TAX TOTAL", "TOTAL
  /// SAVINGS". ("TOTAL IVA INCLUIDO" is the bill.)
  static final RegExp _partTotal = RegExp(
    r'total\s*(?:de\s*|del\s*|en\s*|of\s*)?(?:los\s*|sus?\s*|tu\s*)?'
    r'(?:ahorr\w*|descuentos?|dsctos?|savings?|saved|discounts?|iva|'
    r'i\.v\.a\.?|impuestos?|tax(?:es)?|vat|igv|itbms|isv|ieps|exento|'
    r'gravad[oa]s?)\b(?!\s*inc)|'
    r'\b(?:ahorro|descuentos?|savings?|discounts?|iva|tax|vat|impuestos?)'
    r'\s*total(?:es)?\b',
    caseSensitive: false,
  );

  /// A balance or a points count: money on a card, not money paid with it
  /// ("SALDO EN TARJETA DE PUNTOS: 185.00").
  static final RegExp _balanceRow = RegExp(
    r'\bsaldo\b|\bbalance\b(?!\s*due)|\bpuntos\b|\bpoints\b|disponible|'
    r'available|acumulad',
    caseSensitive: false,
  );

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
      // "47500" for 475.00: a faint decimal point is easily lost.
      pointless: decimalToken == null &&
              exponent == 2 &&
              RegExp(r'^\d{3,7}$').hasMatch(token[0]!)
          ? int.parse(token[0]!)
          : null,
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
      if (_cashRow.hasMatch(row) || _balanceRow.hasMatch(row)) continue;
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
    int? taxTotal;
    var sawTax = false;
    var change = 0;
    final paid = <int>[];
    for (final row in rows) {
      final v = _lastAmount(row, exponent);
      if (v == null || v <= 0) continue;
      if (_subtotalRow.hasMatch(row)) {
        if (v > subtotal) subtotal = v;
      } else if (_taxRow.hasMatch(row) && !_taxBase.hasMatch(row)) {
        // "TOTAL IVA 41.66" restates the tax rows; it is not one more.
        if (_partTotal.hasMatch(row)) {
          taxTotal = v;
        } else {
          tax += v;
        }
        sawTax = true;
      } else if (_changeRow.hasMatch(row)) {
        change = v;
      } else if (_paidRow.hasMatch(row) && !_balanceRow.hasMatch(row)) {
        paid.add(v);
      }
    }
    if (taxTotal != null) tax = taxTotal;
    final computed = subtotal > 0 && sawTax ? subtotal + tax : null;
    final paidNet = [for (final p in paid) p - change];

    // The subtotal is a floor: a "total" below it is a misread (often the
    // tip). A discount printed under the subtotal lowers that floor
    // ("SUBTOTAL 2,297.00" / "DESCUENTO -229.70" / "TOTAL 2,067.30").
    var discount = 0;
    var underSubtotal = false;
    for (final row in rows) {
      if (_subtotalRow.hasMatch(row)) {
        underSubtotal = true;
        continue;
      }
      if (!underSubtotal || !_offSubtotal.hasMatch(row)) continue;
      final v = _lastAmount(row.replaceAll('-', ' '), exponent);
      if (v != null && v > 0) discount += v;
    }
    final floor = discount < subtotal ? subtotal - discount : subtotal;
    final candidates = _keywordTotals(rows, exponent, floor);
    // Tips and service charges printed on their own rows: the gap between
    // the items (or the subtotal) and a total that includes them.
    var tips = 0;
    final tipRows = <(int, int)>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (!_tipOnly.hasMatch(row) || _tipIncluded.hasMatch(row)) continue;
      if (_totalPriority(row) >= 0 || _subtotalRow.hasMatch(row)) continue;
      final v = _lastDecimalAmount(row, exponent);
      if (v != null && v > 0) {
        tips += v;
        tipRows.add((i, v));
      }
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

    final printed = _decimalAmounts(rows, exponent);
    final computedPrinted =
        computed != null && printed.any((a) => _near(a, computed));

    // Readings of the receipt independent of the item lines.
    bool backedByTotals(int amount) {
      if (_ladder(rows, exponent, amount)) return true;
      if (computed != null &&
          (_near(computed, amount) ||
              (tips > 0 && _near(computed + tips, amount)))) {
        return true;
      }
      // The subtotal already has the tax inside it (the tax row is for
      // information), so the total repeats it or adds only the tip:
      // "SUBTOTAL Q250.00 / IVA 12% Q26.79 / PROPINA Q25.00 / TOTAL
      // Q275.00". Not when subtotal plus tax is itself printed.
      if (subtotal > 0 && !computedPrinted) {
        if (_near(subtotal, amount)) return true;
        if (tips > 0 && _near(subtotal + tips, amount)) return true;
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

    // A later total that is this one plus the tax rows, or plus the tip
    // between them, is the bill: "TOTAL NETO 20,25 / IVA 0,81 / TOTAL
    // 21,06", "TOTAL A PAGAR 475.00 / PROPINA 47.50 / TOTAL 522.50".
    final first = pick;
    if (first != null) {
      for (final c in candidates) {
        if (c.weak || c.row <= first.row || c.amount <= first.amount) continue;
        final gap = c.amount - first.amount;
        var tipsBetween = 0;
        for (final (row, tip) in tipRows) {
          if (row > first.row && row < c.row) tipsBetween += tip;
        }
        if ((sawTax && tax > 0 && _near(gap, tax)) ||
            (tipsBetween > 0 && _near(gap, tipsBetween))) {
          pick = c;
          break;
        }
      }
    }

    if (pick != null) {
      // A tip printed under the total and paid in cash: what was handed
      // over, less the change, is the total plus that tip ("TOTAL 428.50 /
      // PROPINA 42.85 / EFECTIVO 500.00 / CAMBIO 28.65").
      var tipsAfter = 0;
      for (final (row, tip) in tipRows) {
        if (row > pick.row) tipsAfter += tip;
      }
      if (tipsAfter > 0) {
        final withTip = pick.amount + tipsAfter;
        if (paidNet.any((p) => _near(p, withTip))) return (withTip, false);
      }
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
      // "TOTAL 47500" where the items add up to 475.00.
      final pointless = pick.pointless;
      if (pointless != null &&
          (backedByTotals(pointless) ||
              (!contradicted(pointless) &&
                  backedByItems(pointless, pick.row)))) {
        return (pointless, false);
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
    final printedAmounts = printed;
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

  /// A label with nothing but its name on the row: "SUBTOTAL", "IVA 16%",
  /// "TOTAL $", "CAMBIO:".
  bool _isBareLabel(String row) {
    final text = row.replaceAll(RegExp(r'\d+(?:[.,]\d+)?\s?%'), ' ');
    if (RegExp(r'\d').hasMatch(text)) return false;
    if (text.length > 36 || _itemsHeading.hasMatch(text)) return false;
    return _subtotalRow.hasMatch(text) ||
        _totalPriority(text) >= 0 ||
        _taxRow.hasMatch(text) ||
        _tipOnly.hasMatch(text) ||
        _tenderLine.hasMatch(text) ||
        _moneyOffRow.hasMatch(text);
  }

  /// A row that is one amount and nothing else: "$475.00", "11.46E".
  bool _isBareAmount(String row, int exponent) {
    if (TextNormaliser.letterCount(row) > 3) return false;
    final tokens =
        _amountToken.allMatches(row.replaceAll(_clockTime, ' ')).toList();
    if (tokens.length != 1) return false;
    final token = tokens.single[0]!;
    return exponent == 0
        ? token.length >= 3
        : RegExp(r'[.,]\d{2}$').hasMatch(token);
  }

  /// Puts each amount back beside its label when the labels were read as
  /// one block and the amounts as another ("SUBTOTAL / IVA / TOTAL" and
  /// then "728.76 / 116.60 / 845.36"), or a label on one row and its
  /// amount on the next. When the block of amounts is longer than the
  /// block of labels the first amounts are the prices of the items above,
  /// and the pairing is kept only if those add up to it.
  List<String> _pairLabelBlocks(List<String> rows, int exponent) {
    final out = <String>[];
    var i = 0;
    while (i < rows.length) {
      if (!_isBareLabel(rows[i])) {
        out.add(rows[i++]);
        continue;
      }
      var j = i;
      while (j < rows.length && _isBareLabel(rows[j])) {
        j++;
      }
      var k = j;
      while (k < rows.length && _isBareAmount(rows[k], exponent)) {
        k++;
      }
      final labels = rows.sublist(i, j);
      final spare = (k - j) - labels.length;
      if (spare >= 0) {
        final loose = rows.sublist(j, j + spare);
        final paired = [
          for (var n = 0; n < labels.length; n++)
            '${labels[n]} ${rows[j + spare + n]}',
        ];
        if (_blockAddsUp(paired, loose, exponent)) {
          out
            ..addAll(loose)
            ..addAll(paired);
          i = k;
          continue;
        }
      }
      out.addAll(labels);
      i = j;
    }
    return out;
  }

  /// Whether labels paired with amounts make sense as the foot of a bill.
  /// [loose] are the amounts before them that got no label.
  bool _blockAddsUp(List<String> paired, List<String> loose, int exponent) {
    if (paired.length == 1 && loose.isEmpty) return true;
    int? total;
    int? subtotal;
    var extras = 0;
    var dearestPart = 0;
    for (final row in paired) {
      final v = _lastAmount(row, exponent);
      if (v == null) return false;
      if (_subtotalRow.hasMatch(row)) {
        subtotal = v;
      } else if (_tenderLine.hasMatch(row) || _moneyOffRow.hasMatch(row)) {
        continue;
      } else if (_taxRow.hasMatch(row) ||
          (_tipOnly.hasMatch(row) && !_tipIncluded.hasMatch(row))) {
        if (!_taxBase.hasMatch(row)) extras += v;
      } else if (_totalPriority(row) >= 0) {
        if (total == null || v > total) total = v;
        continue;
      }
      if (v > dearestPart) dearestPart = v;
    }
    if (loose.isEmpty) return total == null || total >= dearestPart;
    if (total == null) return false;
    var items = 0;
    for (final row in loose) {
      items += _lastAmount(row, exponent) ?? 0;
    }
    return _near(items, total) ||
        _near(items + extras, total) ||
        (subtotal != null &&
            (_near(items, subtotal) || _near(subtotal + extras, total)));
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
      if (_isNotTotal(row) || _tenderLine.hasMatch(row)) continue;
      if (_partTotal.hasMatch(row)) continue;
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
          TextNormaliser.letterCount(rows[i + 1]) < 4 &&
          // Several amounts under a label are a table ("TOTAL CON PROPINA"
          // over "522.50 546.25 570.00"), not that label's amount.
          _decimalAmounts([rows[i + 1]], exponent).length <= 1) {
        read = _lastAmountToken(rows[i + 1], exponent);
      }
      if (read == null) continue;
      if (read.amount <= 0 || read.amount < floor) continue;
      out.add(_Candidate(
        row: i,
        priority: priority,
        amount: read.amount,
        signless: read.signless,
        pointless: read.pointless,
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

  /// A figure as money is printed: "1,234.50", "45.000", "125". Not the
  /// start of a date ("CAD 12/2027" is an expiry, not Canadian dollars).
  static const String _figure =
      r'(?:\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)'
      r'(?![\d/]|-\d)';

  /// A figure with two decimals after a point: "1,234.50".
  static const String _figure2 = r'(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}(?!\d)';

  /// "MXN: 570.00", "USD$ 21.50", "Total (MXN) $5,361.24".
  static final RegExp _codeBeforeAmount = RegExp(
    '(?<![A-Za-z])(${Currencies.common.join('|')})(?![A-Za-z])'
    '\\)?\\s?[:=]?\\s?\\\$?\\s?($_figure)',
  );

  /// "570.00 MXN".
  static final RegExp _codeAfterAmount = RegExp(
    '\\d[.,]\\d{2}\\s?(${Currencies.common.join('|')})(?![A-Za-z])',
  );

  /// Evidence a currency needs before it is believed, by how it is named.
  /// A sign of its own ("£", "Bs", "R$") needs one sighting. Three capitals
  /// need a total row or three other rows: "COMPRA USD 17.80" is an
  /// exchange rate, "BIC PEN 1.99" a pen.
  static const int _signEvidence = 1;
  static const int _codeEvidence = 3;

  /// A single letter counts only beside a total: "GRINGA Q 130.00" is a
  /// dish with cheese and "VOLUMEN L 35.24" is litres.
  static const int _letterEvidence = 3;

  /// Signs and abbreviations that only one currency uses, beside a figure.
  static final List<(RegExp, String, int)> _signs = [
    (
      RegExp('(?<![A-Za-z])U\\.?S\\.?\\s?\\\$\\s?$_figure'),
      'USD',
      _signEvidence,
    ),
    (RegExp('(?<![A-Za-z])U\\\$S\\s?$_figure'), 'USD', _signEvidence),
    (RegExp('(?<![A-Za-z])MX\\s?\\\$\\s?$_figure'), 'MXN', _signEvidence),
    (RegExp('(?<![A-Za-z])R\\\$\\s?$_figure'), 'BRL', _signEvidence),
    (RegExp('(?<![A-Za-z])S/\\.?\\s?$_figure'), 'PEN', _signEvidence),
    (RegExp('₡\\s?$_figure'), 'CRC', _signEvidence),
    (RegExp('£\\s?$_figure'), 'GBP', _signEvidence),
    (RegExp('€\\s?$_figure|\\d[.,]\\d{2}\\s?€'), 'EUR', _signEvidence),
    (RegExp('[₹]\\s?$_figure'), 'INR', _signEvidence),
    (RegExp('[₦]\\s?$_figure'), 'NGN', _signEvidence),
    (RegExp('[₴]\\s?$_figure|\\d[.,]\\d{2}\\s?₴'), 'UAH', _signEvidence),
    (RegExp('[₺]\\s?$_figure|\\d[.,]\\d{2}\\s?₺'), 'TRY', _signEvidence),
    (RegExp('[₱]\\s?$_figure'), 'PHP', _signEvidence),
    (RegExp('[฿]\\s?$_figure'), 'THB', _signEvidence),
    (RegExp('[₩]\\s?$_figure'), 'KRW', _signEvidence),
    (RegExp('[₫]\\s?$_figure|\\d\\s?₫'), 'VND', _signEvidence),
    (RegExp('[₵]\\s?$_figure'), 'GHS', _signEvidence),
    (RegExp('\\d[.,]\\d{2}\\s?zł'), 'PLN', _signEvidence),
    // "Bs 52,40", "Bs.S 52,40", "Bs.D 52,40", "BS. 52,40".
    (
      RegExp('(?<![A-Za-z])B[sS]\\.?\\s?[SDF]?\\.?\\s?[:=]?\\s?$_figure'),
      _bolivarSign,
      _signEvidence,
    ),
    // Honduras: "Lps. 350.00", "L 350.00", "L. 350.00".
    (
      RegExp('(?<![A-Za-z0-9])L(?:ps|PS)\\.?\\s?$_figure'),
      'HNL',
      _signEvidence,
    ),
    (RegExp('(?<![A-Za-z0-9])L\\.?\\s?$_figure2'), 'HNL', _letterEvidence),
    // Guatemala: "Q125.00", "Q 125.00", "Q. 125.00".
    (RegExp('(?<![A-Za-z0-9])Q\\.?\\s?$_figure2'), 'GTQ', _letterEvidence),
  ];

  /// "Bs" is the bolivar, or the boliviano on a receipt from Bolivia.
  static const String _bolivarSign = 'Bs';

  static final RegExp _monedaNacional = RegExp(r'\bM\.\s?N\.?');

  /// A bare "$" beside a figure (not "R$", "US$", "MX$").
  static final RegExp _bareDollar =
      RegExp('(?<![A-Za-z])\\\$\\s?$_figure');

  /// Currencies that are never written with a "$": on their receipts a "$"
  /// amount is a price in dollars for reference ("REF \$ 14,50").
  static const Set<String> _noDollarSign = {
    'VES', 'GTQ', 'HNL', 'CRC', 'PEN', 'GBP', 'EUR', 'BOB',
  };

  /// Every amount on [row] that names its currency: the code, where the
  /// name and figure sit in the row, and the evidence that kind of name
  /// needs.
  List<_CurrencyMark> _currencyMarks(String row) {
    final marks = <_CurrencyMark>[];
    final totalRow = _totalPriority(row) >= 0;
    for (final m in _codeBeforeAmount.allMatches(row)) {
      // A whole number after three capitals is money only beside a word
      // for the total: "TOTAL MXN 90", not "LOTE 12 CAD 122027".
      if (!totalRow && !RegExp('[.,]').hasMatch(m[2]!)) continue;
      marks.add(_CurrencyMark(m[1]!, m.start, m.end, _codeEvidence));
    }
    for (final m in _codeAfterAmount.allMatches(row)) {
      marks.add(_CurrencyMark(m[1]!, m.start, m.end, _codeEvidence));
    }
    for (final (pattern, code, needed) in _signs) {
      if (needed == _letterEvidence && !totalRow) continue;
      for (final m in pattern.allMatches(row)) {
        final currency = code != _bolivarSign
            ? code
            : defaultCurrency == 'BOB'
                ? 'BOB'
                : 'VES';
        marks.add(_CurrencyMark(currency, m.start, m.end, needed));
      }
    }
    return marks;
  }

  /// The receipt's currency, whether the receipt itself says so, and the
  /// other currencies it also gives amounts in.
  ///
  /// Each row that names a currency beside an amount counts once, three
  /// times on a total row; an amount in words that names its currency
  /// ("QUETZALES") counts as a total row. The most named wins, the home
  /// currency on a tie.
  static final RegExp _exchangeRateRow = RegExp(
    r'tipo\s+de\s+cambio|\bt\.?\s?c\.?\s*[:=]|\btasa\b|exchange\s+rate',
    caseSensitive: false,
  );

  ((String, bool), Set<String>) _detectCurrency(List<String> rows) {
    final scores = <String, int>{};
    final needed = <String, int>{};
    final firstRow = <String, int>{};
    void count(String code, int weight, int needs, int row) {
      scores[code] = (scores[code] ?? 0) + weight;
      final least = needed[code];
      if (least == null || needs < least) needed[code] = needs;
      firstRow.putIfAbsent(code, () => row);
    }

    for (var i = 0; i < rows.length; i++) {
      // A rate row names both currencies ("TIPO DE CAMBIO Q7.70 x
      // US\$1.00"); it says nothing about which the bill is in.
      if (_exchangeRateRow.hasMatch(rows[i])) continue;
      final weight = _totalPriority(rows[i]) >= 0 ? 3 : 1;
      final onRow = <String, int>{};
      for (final mark in _currencyMarks(rows[i])) {
        final least = onRow[mark.code];
        if (least == null || mark.needed < least) {
          onRow[mark.code] = mark.needed;
        }
      }
      onRow.forEach((code, needs) => count(code, weight, needs, i));
    }
    for (final words in AmountInWords.find(rows)) {
      final code = words.currency;
      if (words.formal && code != null) count(code, 3, 1, rows.length);
    }
    final named = [
      for (final code in scores.keys)
        if (scores[code]! >= needed[code]!) code,
    ];
    if (named.isEmpty) {
      final joined = rows.join('\n');
      if (_monedaNacional.hasMatch(joined)) {
        return ((defaultCurrency, true), const {});
      }
      return ((defaultCurrency, false), const {});
    }
    named.sort((a, b) {
      if (scores[a] != scores[b]) return scores[b]!.compareTo(scores[a]!);
      if (a == defaultCurrency) return -1;
      if (b == defaultCurrency) return 1;
      return firstRow[a]!.compareTo(firstRow[b]!);
    });
    final best = named.first;
    final others = {...named.skip(1)};
    if (best != defaultCurrency && _isEquivalentOnly(rows, best)) {
      return ((defaultCurrency, false), {best, ...others});
    }
    return ((best, true), others);
  }

  /// Whether [code] is only the bill restated in dollars or euros for the
  /// visitor: named on total rows and nowhere else ("TOTAL USD 84.07"),
  /// beside a total with no currency named that is more than twice or less
  /// than half as much ("TOTAL \$1,530.00"). A tip or a tax never changes a
  /// total that much; an exchange rate does.
  bool _isEquivalentOnly(List<String> rows, String code) {
    if (code != 'USD' && code != 'EUR') return false;
    final named = <int>[];
    final plain = <int>[];
    for (final row in rows) {
      final marks = _currencyMarks(row);
      final inCode = marks.any((m) => m.code == code);
      if (_totalPriority(row) < 60) {
        if (inCode) return false;
        continue;
      }
      if (_isNotTotal(row) || _tenderLine.hasMatch(row)) continue;
      if (_partTotal.hasMatch(row)) continue;
      final value = _lastDecimalAmount(row, 2);
      if (value == null || value <= 0) continue;
      if (marks.isEmpty) {
        plain.add(value);
      } else if (inCode) {
        named.add(value);
      }
    }
    return plain.any(
      (p) => named.isNotEmpty && named.every((n) => p > n * 2 || p * 2 < n),
    );
  }

  /// The rows without the amounts given in a currency other than the
  /// receipt's own: "TOTAL REF USD 14,50" under a total in bolivares,
  /// "TOTAL USD 84.07" under a total in pesos. Those restate the bill; they
  /// are not a second thing paid.
  List<String> _ownCurrencyRows(
    List<String> rows,
    String currency,
    Set<String> others,
  ) {
    final foreign = {...others}..remove(currency);
    final ownSign = rows.any(
      (row) => _currencyMarks(row).any((m) => m.code == currency),
    );
    final dollarsForeign = ownSign && _noDollarSign.contains(currency);
    if (foreign.isEmpty && !dollarsForeign) return rows;
    final out = <String>[];
    for (final row in rows) {
      final cuts = <(int, int)>[
        for (final mark in _currencyMarks(row))
          if (foreign.contains(mark.code)) (mark.start, mark.end),
        if (dollarsForeign)
          for (final m in _bareDollar.allMatches(row)) (m.start, m.end),
      ];
      if (cuts.isEmpty) {
        out.add(row);
        continue;
      }
      // From the end of the row backwards, so the places stay true; two
      // names for one amount ("USD $ 21.50") are cut once.
      cuts.sort((a, b) => b.$1.compareTo(a.$1));
      var text = row;
      var cutFrom = row.length;
      for (final (from, to) in cuts) {
        final end = to < cutFrom ? to : cutFrom;
        if (from >= end) continue;
        text = text.replaceRange(from, end, ' ');
        cutFrom = from;
      }
      // Nothing but the label left: the whole row was the other currency.
      out.add(RegExp(r'\d').hasMatch(text)
          ? TextNormaliser.collapseSpaces(text)
          : '');
    }
    return out;
  }
}

/// An amount on a row that names its currency.
class _CurrencyMark {
  const _CurrencyMark(this.code, this.start, this.end, this.needed);

  final String code;
  final int start;
  final int end;

  /// The score a currency named only this way must reach to be believed.
  final int needed;
}

/// An amount read from a row.
class _Reading {
  const _Reading(
    this.amount, {
    required this.bare,
    this.signless,
    this.pointless,
  });

  final int amount;

  /// A whole number with no decimals or separators ("24").
  final bool bare;

  /// The amount if its first digit was really a misread "$".
  final int? signless;

  /// The amount if a whole number is really a price whose decimal point
  /// was not read ("47500" for 475.00).
  final int? pointless;
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
    this.pointless,
  });

  final int row;
  final int priority;
  final int amount;

  /// A bare whole number on a receipt whose prices have decimals.
  final bool weak;

  /// The amount if its first digit was really a misread "$".
  final int? signless;

  /// The amount if its decimal point was not read.
  final int? pointless;
}

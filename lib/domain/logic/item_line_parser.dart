import 'text_normaliser.dart';

/// One purchased item read from the cropped item area.
class ReceiptItem {
  const ReceiptItem({
    required this.description,
    this.quantity,
    this.amountText,
    this.firstRow = -1,
    this.lastRow = -1,
  });

  final String? quantity;
  final String description;
  final String? amountText;

  /// Indexes of the OCR rows this item came from (-1 when not tracked).
  final int firstRow;
  final int lastRow;
}

/// How one receipt prints its figures, worked out from all of its rows.
class _Style {
  const _Style({
    this.oneDecimal = false,
    this.wholePrices = false,
    this.quantityColumn = false,
    this.flags = '',
    this.bareWhole = false,
    this.quantityAbove = false,
  });

  /// Prices with one decimal ("110.0").
  final bool oneDecimal;

  /// Prices with no decimals ("64.000", "$8500").
  final bool wholePrices;

  /// Item rows begin with a quantity ("1 CAFE", "2 PAN").
  final bool quantityColumn;

  /// Letters this receipt prints after its prices as tax marks although
  /// they could be a size: "1.15 G" (gravado) on every row.
  final String flags;

  /// Prices are bare whole figures ("1 CHURRASQUITO 35"), as market
  /// stalls and comedores print them.
  final bool bareWhole;

  /// A quantity row ("2 x 5.50") belongs to the item under it whenever its
  /// sum is that item's price.
  final bool quantityAbove;

  _Style copyWith({String? flags, bool? bareWhole, bool? quantityAbove}) =>
      _Style(
        oneDecimal: oneDecimal,
        wholePrices: wholePrices,
        quantityColumn: quantityColumn,
        flags: flags ?? this.flags,
        bareWhole: bareWhole ?? this.bareWhole,
        quantityAbove: quantityAbove ?? this.quantityAbove,
      );
}

/// One OCR row split into its wording and the figures after it.
class _Row {
  const _Row({
    required this.head,
    required this.tail,
    required this.amounts,
    required this.complete,
    this.quantity,
    this.times,
  });

  /// The wording: "2 AGUA MINERAL" of "2 AGUA MINERAL 45.00 90.00".
  final String head;

  /// The figure tokens after it, as printed.
  final List<String> tail;

  /// The prices among them, tidied ("-11.00" for "11.00-").
  final List<String> amounts;

  /// The quantity written with the figures ("2" of "2 x 55.00", "0.450 kg").
  final String? quantity;

  /// "x2" or "X6" written as one word among the figures, as printed: how
  /// many, or a pack size. [quantity] then holds its number.
  final String? times;

  /// Whether the row ends in a finished price, not in "12.35=" or "x".
  final bool complete;

  String? get amount => amounts.isEmpty ? null : amounts.last;
  bool get figuresOnly => head.isEmpty && tail.isNotEmpty;
}

/// What the number in front of a name is, as far as the row itself tells.
enum _LeadKind {
  /// "2 TACOS".
  plain,

  /// "4 7707654300019 JABON": a number, then a barcode.
  coded,

  /// "002 TACO", "001 1001 PRATO": printed with zeros in front.
  padded,
}

/// The number one item's row opened with.
class _Lead {
  const _Lead(this.text, this.kind, {this.used = false, this.kept = false});

  final String text;
  final _LeadKind kind;

  /// It became the item's quantity.
  final bool used;

  /// It was left in front of the name ("12 ALITAS BBQ" ordered "x2").
  final bool kept;
}

/// Whether a row belongs to the totals block.
enum _Summary {
  no,
  yes,

  /// Opens with a word of the totals block but reads as a product
  /// ("TABLE WATER 0.00"); where it stands on the receipt decides.
  product,
}

/// Turns OCR rows from the item crop into item lines, dropping anything that
/// must not be translated (totals, tax, tips, payment and card details).
class ItemLineParser {
  ItemLineParser._();

  // ------------------------------------------------------- totals and headers

  /// Words that open a totals, tax, payment or header row and never a
  /// product. Whole words (\b) so items such as "Taxi" or "Netflix" are not
  /// dropped; a few are prefixes on purpose (autoriz-ación, aprobad-o).
  /// Matched on [_fold]ed text, so "T0TAL", "lVA" and "Sub-tota1" are found.
  static final RegExp _strict = _folded(
    r'^(?:sub\s*-?\s*t(?:o?tal|tl)\b|'
    // Tax: "IVA 16%", "I.V.A.", "IMPUESTOS", "SALES TAX", "IGTF 3%".
    r'i\.?\s?v\.?\s?a(?:\b|\d)|ieps|i\.e\.p\.s|isr\b|ish\b|i\.\s?s\.\s?h\b|'
    r'igtf\b|'
    r'impoconsumo|impuestos?\b|(?:sales|state|city)\s+tax|vat\b|gst\b|'
    // The fuel tax printed under the fuel in Guatemala: "IDP Q 40.06"
    // (not a product such as "IDP APPLICATION FEE").
    // Also "I.D.P.", "IDP SUPER Q 4.70 X GAL", "IDP (4.70 X GALON)", and
    // the Salvadoran levies "FOVIAL" and "COTRANS".
    r'i\.?\s?d\.?\s?p\b\.?\s*(?:incluido\s*)?:?\s*(?:[$(-]|\d|$)|'
    r'idp\b.*\bgal|fovial\b|cotrans\b|'
    // The sums of an electronic invoice: "TOTALES: 0.00 1,514.00".
    r'totales\b|'
    // The price of one, printed as a field: "PRECIO UNITARIO $23.89".
    r'(?:precio|valor)\s+unitario|unit\s+price|price\s?/\s?gal|'
    // "PRECIO $23.89": the same field with its colon lost.
    r'precio\s*\$?\s*\d[\d.,]*\s*$|'
    // Tourism levies on a hotel night: "INGUAT 10%", "TURISMO 5%",
    // "CONTRIBUCION TURISMO 5%".
    r'inguat\b|(?:contribucion\s+(?:(?:de|al|para)\s+)?)?turismo\s+\d|'
    // A day's total on a folio.
    r'total\s+(?:del?\s+)?dia\b|'
    // Tip and service: "PROPINA", "CARGO POR SERVICIO", "SERVICIO 10%",
    // "OPTIONAL SERVICE CHARGE", "TAXA DE SERVICO", "GORJETA".
    r'propina|gratuity|gorjeta|service\s*charge|'
    r'(?:optional|discretionary|suggested)\s+(?:service|gratuity|tip)|'
    r'cargo\s+(?:por|de|x)\s+servicio|servicio\s*\d|servico\s*\d|taxa\b|'
    // Payment: "EFECTIVO", "RECIBIDO", "SU PAGO", "MONEDERO", "ANTICIPO".
    r'efectivo|dinheiro|master\s*card|amex|american\s*express|'
    r'anticipo|abono\b|recibido|entregado|tendered|su\s+pago|pag[ao]\s+con|'
    r'pagad[oa]\b|payment|pagamento|monedero|puntos\b|'
    // The change given back ("CAMBIO $0.00", "CHANGE DUE 1.50"), not a
    // swap on an item ("CAMBIO L. LIGHT": change to light milk).
    r'(?:su\s+)?(?:cambio|change)(?:\s+due)?\s*:?\s*(?:mxn|usd|m\.?n\.?)?\s*'
    r'(?:[$-]|\d|$)|vuelto\b|troco\b|'
    // Sums under the items: "NETO", "GRAVADO", "EXENTO", "BASE IMPONIBLE",
    // "SUMAS", "VENTAS GRAVADAS", "A PAGAR", "IMPORTE", "MONTO".
    r'net[oa]?\b|gravad[oa]s?\b|exent[oa]s?\b|no\s+sujet|'
    r'base\s*(?:imponible|gravable|iva)?\s*:?\s*(?:[$-]|\d|$)|'
    r'ventas?\b|sumas?\b|a\s+pagar|por\s+pagar|to\s+pay\b|'
    r'importe|amount|monto\b|redondeo|rounding|'
    // Savings and surcharges: "DESCUENTOS 0,00", "USTED AHORRO 15.00".
    r'descuentos\b|recargos?\b|(?:usted\s+)?ahorr|you\s+saved|savings\b|'
    // Exchange rates: "TIPO DE CAMBIO 17.50", "T.C. 17.50", "Tasa del día".
    r'tipo\s+de\s+cambio|t\.?c\.?\s*\d|tasa\s*(?:del?\s+)?(?:dia|cambio|bcv|:)|'
    // Header and footer: who served, tax ids, phones, thanks, approvals.
    r'folio|mesero|waiter|server\b|cajero|cashier|(?:le\s+)?atendio|'
    r'comensales|personas|guests|covers\b|rfc\b|r\.f\.c|nit\b|nrc\b|rif\b|'
    r'ruc\b|cnpj|tels?\b|telefono|phone|whatsapp|gracias|thank|obrigad|'
    r'autoriz|aprobad|approved|auth(?:ori|\b)|firma\b|signature|'
    r'items?\s+sold)',
  );

  /// Words of the totals block that can also open a product's name
  /// ("TOTAL 0% YOGUR", "TIP TOP PAN", "TABLE WATER", "MESA DE QUESOS",
  /// "TARJETA DE REGALO", "DATE SCONE"). See [_summaryOf].
  static final RegExp _soft = _folded(
    r'^(?:total|tip|tarjeta|card|cartao|visa|credito|debito|credit|debit|'
    r'mesa|table|'
    r'fecha|date|hora|time|ticket|cuenta|pagos?|saldo|balance|cash|tax)\b',
  );

  /// The count of things bought: "ARTICULOS 4", "NO. DE ARTICULOS: 2",
  /// "ARTICULOS VENDIDOS: 3", "PIEZAS 5".
  /// And with the count first, or in Portuguese: "5 ITEMS", "TOTAL
  /// ARTICULOS 6", "QTD. TOTAL DE ITENS 4".
  static final RegExp _count = _folded(
    r'^(?:(?:(?:no|num|numero|cantidad|cant|qtd|qtde|quantidade|total)\.?\s*'
    r'(?:total\s+)?(?:de\s+)?)?'
    r'(?:articulos|arts|piezas|pzas|productos|items|itens)\b\.?'
    r'(?:\s+(?:vendidos|comprados|sold))?\s*[:#=]?\s*\d+\s*$|'
    // Not "12 PIEZAS": the pieces of a dish, printed under it.
    r'\d{1,3}\s+(?:articulos?|arts?|productos?|items?|itens)\b'
    r'(?:\(s\))?\.?(?:\s+(?:vendidos|comprados|sold))?\s*$|'
    // "ART. VENDIDOS 2", "NRO. ARTICULOS 2", "ITEM COUNT 2", "UNIDADES
    // VENDIDAS 2", "NUMBER OF ITEMS SOLD = 2".
    r'(?:(?:nro|number\s+of)\.?\s*)?(?:arts?|articulos|items?|unidades)\.?'
    r'\s+(?:vendid[oa]s|count|sold)\s*[:#=]?\s*\d+\s*$|'
    r'nro\.?\s*(?:de\s+)?articulos\s*[:#=]?\s*\d+\s*$)',
  );

  /// A tax under any name on a dated row of a statement: "11/16/26
  /// OCCUPANCY TAX 9.45", "HOTEL/MOTEL TAX". Without a date in front a
  /// named tax may be the thing paid for ("DEPARTURE TAX $30.00").
  static final RegExp _taxWord = RegExp(r'\btax(?:es)?\b', caseSensitive: false);

  /// A named tax printed with its rate: "State Occupancy Tax 6% 6.54",
  /// "CITY PARKING TAX 8.25% 1.68". Passed over wherever it stands.
  static final RegExp _ratedTax = RegExp(
    r'\btax(?:es)?\b.*\d\s?%|\d\s?%.*\btax(?:es)?\b',
    caseSensitive: false,
  );

  /// Levy and field rows that can stand between two items: they are not
  /// listed and do not end the list ("IDP Q 40.06" then "ACEITE 45.00").
  static final RegExp _levy = _folded(
    r'^(?:i\.?\s?d\.?\s?p\b|fovial\b|cotrans\b|inguat\b|'
    r'(?:contribucion\s+(?:(?:de|al|para)\s+)?)?turismo\s+\d|'
    r'(?:precio|valor)\s+unitario|unit\s+price|price\s?/\s?gal|'
    r'precio\s*\$?\s*\d|i\.\s?s\.\s?h\b)',
  );

  /// "DESCUENTO 0.00": nothing taken off. Printed under every line by some
  /// tills; neither an item nor the end of the list.
  static final RegExp _zeroDiscount =
      _folded(r'^descuento\s*:?\s*\$?\s*0+[.,]00\s*$');

  /// A saving or discount row with a name after it: "AHORRO CAFE NESCAFE
  /// -12.00". It is a line of the list when that name is the product above.
  static final RegExp _savingOn = _folded(r'^(?:ahorro|descuentos|savings)\s');

  /// The tax on a hotel night under its many labels: "IMP. HOSPEDAJE 3%",
  /// "3% HOSPEDAJE", "IMPUESTO SOBRE HOSPEDAJE". Not the night itself
  /// ("HOSPEDAJE 2,150.00").
  static final RegExp _lodgingTax = RegExp(
    // "3% HOSPEDAJE", "HOSPEDAJE 3% 64.50" (the rate, then only the
    // amount), "IMP. HOSPEDAJE", "IMP. HOSP. 3%", "IMP. S/HOSPEDAJE".
    r'^\W*(?:\d{1,2}(?:[.,]\d+)?\s?%\s+(?:(?:de|sobre)\s+)?hosp(?:edaje)?\b|'
    r'hospedaje\s+\d{1,2}(?:[.,]\d+)?\s?%\s+[$\d]|'
    r'imp(?:uesto|to)?s?\.?\s+(?:(?:al?|sobre|de|el)\s+|s/\s?)*hosp(?:edaje)?\b)',
    caseSensitive: false,
  );

  /// "TAX1 2.51", "TAX 2 0.80": a numbered tax row of a US till.
  static final RegExp _numberedTax =
      RegExp(r'^\W*tax\s?\d\b', caseSensitive: false);

  /// A masked card number read as a word: "XXXX1111" (its digits folded
  /// to letters).
  static final RegExp _masked = RegExp(r'^x{3,}[iosb]*$');

  /// The subtotal or total row itself.
  static final RegExp _totalWord = _folded(
    r'^(?:sub\s*-?\s*t(?:o?tal|tl)|total|(?:balance|amount)\s+due)\b',
  );

  /// Words found on totals, tax and payment rows. A priced row holding a
  /// word of three letters or more that is not one of these names a
  /// product, even if it opens with "TOTAL" or "MESA".
  static final Set<String> _vocabulary = {
    for (final word in const [
      // joining words
      'de', 'del', 'las', 'los', 'con', 'sin', 'por', 'para', 'sus', 'the',
      'and', 'for', 'not', 'with',
      // sums
      'total', 'totales', 'subtotal', 'sub', 'importe', 'monto', 'valor',
      'suma', 'sumas', 'amount', 'order', 'bill', 'check', 'invoice', 'sale',
      'sales', 'purchase', 'gran', 'grand', 'general', 'final', 'neto',
      'neta', 'net', 'bruto', 'venta', 'ventas', 'compra', 'consumo',
      'cuenta', 'due', 'paid', 'pay', 'pagar', 'pagado', 'pagada', 'pago',
      'pagos', 'cobrar', 'cobrado',
      // tax, tip and service
      'iva', 'impuesto', 'impuestos', 'tax', 'taxes', 'vat', 'incluido',
      'incluida', 'incl', 'included', 'including', 'excl', 'exento',
      'exenta', 'gravado', 'gravada', 'base', 'imponible', 'gravable',
      'propina', 'tip', 'tips', 'servicio', 'service', 'charge', 'cargo',
      'sugerida', 'sugerido', 'suggested',
      // payment
      'tarjeta', 'tarjetas', 'card', 'cards', 'credito', 'debito', 'credit',
      'debit', 'visa', 'mastercard', 'master', 'amex', 'american', 'express',
      'efectivo', 'cash', 'cambio', 'change', 'vuelto', 'recibido',
      'entregado', 'tendered', 'tend', 'bancaria', 'bancario', 'banco',
      'terminal', 'saldo', 'balance', 'anterior',
      // money
      'mxn', 'usd', 'gtq', 'cop', 'ves', 'gbp', 'eur', 'pesos', 'peso',
      'dolares', 'dolar', 'quetzales', 'bolivares', 'moneda', 'nacional',
      'letra', 'letras',
      // counts and discounts
      'articulo', 'articulos', 'producto', 'productos', 'piezas', 'items',
      'item', 'sold', 'vendidos', 'descuento', 'descuentos', 'discount',
      'discounts', 'ahorro', 'savings',
      // header
      'cargos', 'charges', 'payment', 'payments', 'abono', 'abonos',
      'price', 'precio', 'charged', 'updated', 'actualizado',
      'sujeto', 'sujetos',
      'sujetas', 'gravados', 'gravadas', 'exentos', 'exentas',
      'ticket', 'folio', 'mesa', 'table', 'fecha', 'date', 'hora', 'time',
      'numero', 'num', 'operacion', 'documento', 'factura', 'cerrada',
      'cerrado', 'pers', 'persona', 'personas', 'guests', 'covers', 'pax',
    ])
      _fold(word),
  };

  static final String _foldedTotal = _fold('total');
  static final RegExp _word = RegExp(r'[a-z]{3,}');

  /// What stands in front of the first word: bullets and rules, and the
  /// rate on rows such as "10% SERVICIO 37.35" or "16% IVA 59.10".
  static final RegExp _leadIn = RegExp(
    r'^[^a-z0-9]*(?:\d{1,2}(?:[.,]\d+)?\s?%[^a-z0-9]*)?',
  );

  /// A pattern for [_fold]ed text, written in plain spelling.
  static RegExp _folded(String source) => RegExp(source.replaceAll('l', 'i'));

  /// Text made comparable for the totals words: lower case, no accents,
  /// spaced-out capitals joined ("T O T A L"), digits read for letters put
  /// back ("T0TAL", "Tota1", "1VA", "5UBTOTAL") and l, I and | made one
  /// letter ("lVA", "TOTAI").
  static String _fold(String text) {
    var t = TextNormaliser.stripDiacritics(text).toLowerCase();
    t = t.replaceAllMapped(
      RegExp(r'\b(?:[a-z] ){3,}[a-z]\b'),
      (m) => m[0]!.replaceAll(' ', ''),
    );
    t = t.split(' ').map((word) {
      if (!RegExp(r'^[a-z0158|.:]+$').hasMatch(word)) return word;
      if (RegExp(r'[a-z]').allMatches(word).length < 2) return word;
      return word
          .replaceAll('0', 'o')
          .replaceAll('1', 'i')
          .replaceAll('5', 's')
          .replaceAll('8', 'b');
    }).join(' ');
    return t.replaceAll('l', 'i').replaceAll('|', 'i');
  }

  /// Classes a cleaned row: part of the totals block, or not, or a product
  /// that only opens with one of its words. A row is a product when it has
  /// a price and a word no totals row uses: "TARJETA DE REGALO 500.00" is
  /// one, "TARJETA CREDITO 392.15" and "TARJETA: ****1234" are not.
  static (_Summary, bool) _summaryOf(String text, _Row row) {
    final t = _fold(text).replaceFirst(_leadIn, '');
    if (t.isEmpty) return (_Summary.no, false);
    final totals = _totalWord.hasMatch(t);
    final words = [
      for (final m in _word.allMatches(t))
        if (!_masked.hasMatch(m[0]!)) m[0]!,
    ];
    final product = words.any((w) => !_vocabulary.contains(w));
    if (_strict.hasMatch(t) ||
        _count.hasMatch(t) ||
        _lodgingTax.hasMatch(text) ||
        _numberedTax.hasMatch(text) ||
        _ratedTax.hasMatch(text)) {
      return (_Summary.yes, totals);
    }
    if (_soft.hasMatch(t)) {
      return row.amount != null && row.head.isNotEmpty && product
          ? (_Summary.product, false)
          : (_Summary.yes, totals);
    }
    // "VENTA TOTAL 70.00", "GRAN TOTAL", "DESCUENTO TOTAL", "o Total": only
    // words of the totals block, "total" among them. "COLGATE TOTAL 45.00"
    // and "1 TOTAL 0% 500G 55.00" are products.
    if (!product &&
        words.contains(_foldedTotal) &&
        !RegExp(r'^\d').hasMatch(t)) {
      return (_Summary.yes, true);
    }
    return (_Summary.no, false);
  }

  /// Section headings printed between items ("BEBIDAS", "--- POSTRES ---")
  /// and seat or course markers ("SILLA 2", "SEAT 1", "--- 2do tiempo ---",
  /// "COURSE 2"): not items, not choices.
  static final RegExp _heading = RegExp(
    r'^\W*(?:alimentos|bebidas|comidas?|postres|entradas|vitrina|barra|'
    r'cocina|bar|cafeter[ií]a|panader[ií]a|reposter[ií]a|food|drinks|'
    r'beverages|desserts|starters|mains|sides|otros|varios|para\s+llevar|'
    r'to\s+go|comer\s+aqu[ií]|eat\s+in|take\s*away|platos?\s+fuertes?|'
    r'sopas|ensaladas|vinos|licores|cervezas|desayunos|'
    r'(?:silla|asiento|seat|comensal|persona|cliente|guest|pax|tiempo|'
    r'course|ronda|round)\s*(?:no\.?|n[°º]|#)?\s*\d{1,2}|'
    r'(?:\d{1,2}\s?(?:er|ro|do|da|to|st|nd|rd|th|[°º])?\.?|primer|segundo|'
    r'tercer|first|second|third)\s*(?:tiempo|course|ronda|round))\W*$',
    caseSensitive: false,
  );

  /// A line taken back: "CANCELADO 1 CERVEZA -55.00", "** VOID **",
  /// "ANULACION", "DEVOLUCION".
  static final RegExp _void = RegExp(
    r'^\W*(?:cancelad[oa]s?|cancelaci[oó]n|cancela|anulad[oa]s?|'
    r'anulaci[oó]n|void(?:ed)?|correcci[oó]n|devoluci[oó]n|refund|'
    r'reversal)\b[\s:*\-]*',
    caseSensitive: false,
  );

  // ------------------------------------------------------ line-by-line parse

  static final RegExp _trailingAmounts = RegExp(
    r'((?:\s+[$£€]?\s?-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}-?)+)\s*$',
  );

  static final RegExp _amount = RegExp(r'-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}-?');

  /// "2 TACOS", "2x TACOS", "2 PZA CONCHA", "2.000 UN ARROZ", and with a
  /// measure "1.5 KG TORTILLA" (the unit is then kept with the quantity).
  static final RegExp _leadingQuantity = RegExp(
    r'^(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:(kgs?|grs?|lbs?|oz|lts?|ml)|x|×|\*|'
    r'pzas?|pz|piezas?|uds?|unds?|unid|uni|un|pcs?|ea)?\.?\s+(?=\D)',
    caseSensitive: false,
  );

  /// "1 175ML SAUVIGNON BLANC", "2 1.5 L AGUA": a quantity before a name
  /// that begins with a measure.
  static final RegExp _quantityThenMeasure = RegExp(
    r'^(\d{1,2})\s+(?=\d+(?:[.,]\d+)?\s?(?:ml|cl|oz|grs?|kgs?|lts?|g|l)\b)',
    caseSensitive: false,
  );

  /// "2 7UP", "1 3 LECHES", "1 1/2 POLLO", "2 20 ALITAS": on a receipt
  /// whose rows begin with a quantity, the first of two figures is it.
  /// Not "1 1/2 KG BARBACOA": one and a half kilos.
  static final RegExp _quantityThenFigure = RegExp(
    r'^(\d{1,2})\s+(?=\d\S*\s*\S*[A-Za-zÀ-ÿ])'
    r'(?!\d+/\d+\s*(?:kgs?|kilos?|lts?|litros?|l|lbs?|libras?|g|grs?)\b)',
    caseSensitive: false,
  );

  /// "1 x 12 ALITAS BBQ", "2 x 7UP 600ML": how many, a times sign, and a
  /// name that begins with a figure.
  static final RegExp _quantityTimesFigure =
      RegExp(r'^(\d{1,2})\s?[xX×]\s+(?=\d\S*\s*\S*[A-Za-zÀ-ÿ])');

  /// "002 TACO PASTOR", "010 TORTILLAS", "001 1001 PRATO": a number printed
  /// with zeros in front: a quantity, or the number of the line (which of
  /// the two, [extract] tells from all the rows).
  static final RegExp _padded = RegExp(r'^(0\d{1,2})\s+(?=\S*[A-Za-zÀ-ÿ0-9])');

  /// The short product code after a line counter: "1001 PRATO EXECUTIVO".
  static final RegExp _shortCode = RegExp(r'^\d{3,6}\s+(?=\S*[A-Za-zÀ-ÿ])');

  /// "30.120 L PREMIUM", "8.524 GAL SUPER": a volume with three decimals,
  /// as a pump measures it. "2.00 LITRO DE HORCHATA" is two of a dish.
  static final RegExp _leadingVolume = RegExp(
    r'^(\d{1,3}[.,]\d{3})\s*(l|lts?|litros?|gal|galones)\.?\s+(?=\D)',
    caseSensitive: false,
  );

  // ------------------------------------------------- whole-block extraction

  /// A price: "12.35", "$12.35", "12.35E" (tax letter), "12.35=", "1,170.00",
  /// "11.00-" (taken off), and as a faint print is read: "S1,170.00" (the
  /// peso sign as S), "59.OO" (O for 0), "l40.00" (l for 1).
  static final RegExp _amountShape = RegExp(
    r'^(-?)(?:[$£€]|S(?=[\dOolI]))?(-?)'
    r'((?:[\dOolI]{1,3}(?:[.,][\dOolI]{3})+|[\dOolI]+)[.,][\dOo]{2})'
    r'(-?)=?[A-Za-z]?$',
  );

  /// A price with no decimals, on receipts that print none: "64.000",
  /// "$8.500", "$8500".
  static final RegExp _wholeShape = RegExp(
    r'^(-?)\$?(-?)(\d{1,3}(?:[.,]\d{3})+|(?<=\$-?)\d+)(-?)$',
  );

  static final RegExp _bareWhole = RegExp(r'^\d{1,5}$');

  static final RegExp _numberToken = RegExp(r'^[$£€]?-?\d+(?:[.,]\d+)?=?$');
  static final RegExp _timesToken = RegExp(r'^[xX×*@]$');

  /// "x2", "X3": how many, written as one word.
  static final RegExp _multiplierToken = RegExp(r'^[xX×](\d{1,3})$');

  static const String _units =
      r'kgs?|kilos?|g|grs?|lbs?|oz|l|lts?|ltr|litros?|ml|gal|gls?|galones|'
      r'pzas?|pz|piezas?|uds?|unds?|unid|uni|un|pcs?|ea';
  static final RegExp _unitToken =
      RegExp('^(?:$_units)\\.?\$', caseSensitive: false);

  /// Units that measure (the quantity keeps them: "0.450 kg", "35.214 L").
  static final RegExp _measureUnit = RegExp(
    r'^(?:kgs?|kilos?|g|grs?|lbs?|oz|l|lts?|ltr|litros?|ml|gal|gls?|'
    r'galones)\.?$',
    caseSensitive: false,
  );

  /// A price per unit: "89.90/kg", "$22.90/KG", "/kg", "/0.54".
  static final RegExp _perUnitToken = RegExp(
    '^(?:[\$£€]?\\d+(?:[.,]\\d+)?)?/(?:(?:$_units)\\.?|[\$£€]?\\d+[.,]\\d+)\$',
    caseSensitive: false,
  );

  /// Tax marks printed after the price: "18.00 A", "3.48 O", "12.40 *",
  /// "45.00 16%". Not G, K, L or M, which after a figure are a size
  /// ("AGUA 1.50 L"), nor X, which may be a times sign.
  static final RegExp _flagToken =
      RegExp(r'^(?:[A-FH-JN-WYZ]|\*{1,2}|\d{1,2}(?:[.,]\d+)?%)$');

  /// The price in [token] as it should be shown, or null if it is not one.
  static String? _asAmount(String token, [_Style style = const _Style()]) {
    var m = _amountShape.firstMatch(token);
    // At least one true digit: "lO.OO" is letters.
    if (m != null && !RegExp(r'\d').hasMatch(m[3]!)) m = null;
    // "1.5OZ" is a measure, not 1.50 with a tax letter Z ("2.5OT" and
    // "12.3OE" are prices whose last zero was read as O).
    if (m != null && RegExp(r'[.,]\d[Oo][Zz]$').hasMatch(token)) m = null;
    // "1.75L", "0.75L": litres. No till marks its tax with an L.
    if (m != null && RegExp(r'\d[Ll]$').hasMatch(token)) m = null;
    if (m == null && style.wholePrices) m = _wholeShape.firstMatch(token);
    if (m == null && style.bareWhole && _bareWhole.hasMatch(token)) {
      return token;
    }
    if (m == null) return null;
    final figures = m[3]!
        .replaceAll(RegExp('[Oo]'), '0')
        .replaceAll(RegExp('[lI]'), '1');
    final negative = m[1] == '-' || m[2] == '-' || m[4] == '-';
    return negative ? '-$figures' : figures;
  }

  /// "1.00" and "2.000" are 1 and 2; "35.214" and "0.450" stay.
  static String _plain(String number) => number
      .replaceAll(RegExp(r'[^0-9.,]'), '')
      .replaceAll(RegExp(r'[.,]0+$'), '');

  /// A number that can stand before a times sign as the quantity: "2",
  /// "1.00", "35.214". "164,60 x" is a price read before its sign.
  static bool _quantityLike(String token) =>
      _numberToken.hasMatch(token) &&
      (_amountShape.firstMatch(token) == null ||
          RegExp(r'[.,]00=?$').hasMatch(token));

  /// Splits a cleaned row into its wording and the figures after it:
  /// "PARIS WARM BOWL 1.00 x 12.35= 12.35E", "MAGNA 35.214 L x 23.99 844.78",
  /// "0.450 kg x 34.90/kg 15.71", "TACO PASTOR x2 44.00", "COCA 18.00 A".
  static _Row _parse(String text, [_Style style = const _Style()]) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    bool amount(String t) => _asAmount(t, style) != null;
    bool number(String t) => _numberToken.hasMatch(t) || amount(t);
    bool figure(String t) =>
        number(t) ||
        _unitToken.hasMatch(t) ||
        _perUnitToken.hasMatch(t) ||
        _timesToken.hasMatch(t);

    // Tax marks after the price are dropped.
    var end = tokens.length;
    var e = end;
    while (e > 1 &&
        (_flagToken.hasMatch(tokens[e - 1]) ||
            (tokens[e - 1].length == 1 && style.flags.contains(tokens[e - 1])))) {
      e--;
    }
    if (e < end && amount(tokens[e - 1])) end = e;

    var headEnd = -1;
    var tailFrom = -1;
    String? quantity;
    String? timesToken;
    // A times sign with nothing but figures after it.
    for (var t = 0; t < end && headEnd < 0; t++) {
      if (!_timesToken.hasMatch(tokens[t])) continue;
      final after = tokens.sublist(t + 1, end);
      if (!after.every(figure)) continue;
      if (after.isNotEmpty && !amount(after.last)) continue;
      final before = t > 0 ? tokens[t - 1] : '';
      final priceNext = after.isEmpty ||
          amount(after.first) ||
          _perUnitToken.hasMatch(after.first) ||
          (after.length > 1 && _unitToken.hasMatch(after[1]));
      if (t >= 2 &&
          priceNext &&
          _unitToken.hasMatch(before) &&
          number(tokens[t - 2])) {
        // "35.214 L x 23.99 844.78", "2 PZA x 15.00 30.00".
        quantity = _measureUnit.hasMatch(before)
            ? '${_plain(tokens[t - 2])} $before'
            : _plain(tokens[t - 2]);
        headEnd = t - 2;
        tailFrom = t;
      } else if (t >= 1 && priceNext && _quantityLike(before)) {
        // "2 x 55.00 110.00", "1.00 x 12.35= 12.35E".
        quantity = _plain(before);
        headEnd = t - 1;
        tailFrom = t;
      } else if (t >= 1 && amount(before)) {
        // "45.00 x 2 90.00", or a price before a sign with the rest under it.
        if (after.length > 1 && RegExp(r'^\d{1,3}$').hasMatch(after.first)) {
          quantity = after.first;
        }
        headEnd = t - 1;
        tailFrom = t - 1;
      } else if (t == 0 || !number(before)) {
        // "TACO PASTOR X 2 44.00"; or a stray mark before the price.
        if (after.length > 1 && RegExp(r'^\d{1,3}$').hasMatch(after.first)) {
          quantity = after.first;
          timesToken = '${tokens[t]} ${after.first}';
        }
        headEnd = t;
        tailFrom = t;
      }
      // Otherwise a size or an offer ("FOTO 4 X 6", "2 X 1"): part of the name.
    }
    if (headEnd < 0) {
      var i = end;
      while (i > 0 &&
          (amount(tokens[i - 1]) ||
              _perUnitToken.hasMatch(tokens[i - 1]) ||
              _multiplierToken.hasMatch(tokens[i - 1]))) {
        i--;
      }
      headEnd = i;
      tailFrom = i;
    }
    final tail = tokens.sublist(tailFrom, end);
    final amounts = [
      for (final t in tail)
        if (_asAmount(t, style) != null) _asAmount(t, style)!,
    ];
    for (final t in tail) {
      final times = _multiplierToken.firstMatch(t);
      if (times != null && quantity == null) {
        quantity = times[1];
        timesToken = t;
      }
    }
    var head = tokens.take(headEnd).toList();
    // "0.450 KG $34.90/KG $15.71": a weight and its price, no wording.
    if (amounts.isNotEmpty &&
        head.isNotEmpty &&
        head.any(number) &&
        head.every((t) => number(t) || _unitToken.hasMatch(t))) {
      // A barcode printed before the quantity is not the quantity
      // ("1045678912 1 PZA 899.00").
      final figures = [
        for (final t in head)
          if (!RegExp(r'^\d{5,}$').hasMatch(t)) t,
      ];
      if (figures.isNotEmpty && number(figures.first)) {
        final unit = figures.length > 1 && _measureUnit.hasMatch(figures[1]);
        quantity ??= unit
            ? '${_plain(figures.first)} ${figures[1]}'
            : _plain(figures.first);
      }
      head = const [];
    }
    return _Row(
      head: head.join(' '),
      tail: tail,
      amounts: amounts,
      quantity: quantity,
      times: timesToken,
      complete:
          tail.isNotEmpty && amount(tail.last) && !tail.last.endsWith('='),
    );
  }

  static final RegExp _edges = RegExp(r'^[\s\-*.·:+>»•~=]+|[\s\-*.·:$]+$');

  /// "l Naranjada": the quantity 1 read as a letter, on receipts whose rows
  /// begin with a quantity.
  static final RegExp _letterOne = RegExp(r'^[lI|]\s+(?=\S{2})');

  /// "1 7501055300075 COCA COLA": quantity, barcode, name.
  static final RegExp _quantityThenCode =
      RegExp(r'^(\d{1,3})\s+\d{5,}\s+(?=\S*[A-Za-zÀ-ÿ])');

  /// A product code before the name: "7501055300075 COCA COLA 600ML",
  /// "PLU 4011 PLATANO", "SKU: 123456 TALADRO".
  static final RegExp _leadingCode = RegExp(
    r'^(?:(?:plu|sku|cod|c[oó]digo|art|ref|clave)\.?\s*[:#]?\s*\d{3,}|\d{5,})'
    r'\s+(?=\S*[A-Za-zÀ-ÿ])',
    caseSensitive: false,
  );

  /// A barcode after the name, with the marks some tills print behind it:
  /// "GV WHL MLK 007874235186 F", "BANANAS 000000004011 KF".
  static final RegExp _trailingCode = RegExp(r'\s+\d{6,}(?:\s+[A-Z]{1,2})?$');

  /// The unit price some tills print after the name: "Salmon @$390.",
  /// "Naranjada @S59.OO".
  static final RegExp _unitPriceNote =
      RegExp(r'\s*@\s*[$S]?\s?[\dOolI][\dOolI.,]*$');

  /// A tax letter in brackets after the name: "REFRESCO COLA (G)".
  static final RegExp _bracketFlag = RegExp(r'\s*\([A-Z]\)$');

  /// The name in [head] without quantity, codes and price notes, and the
  /// quantity that stood in front of it.
  static (String, String?) _nameOf(
    String head, [
    _Style style = const _Style(),
  ]) {
    var t = head.replaceAll(_edges, '').trim();
    String? quantity;
    final one = style.quantityColumn ? _letterOne.firstMatch(t) : null;
    final padded = _padded.firstMatch(t);
    final volume = _leadingVolume.firstMatch(t);
    final coded = _quantityThenCode.firstMatch(t);
    final figure = _quantityTimesFigure.firstMatch(t) ??
        _quantityThenMeasure.firstMatch(t) ??
        (style.quantityColumn ? _quantityThenFigure.firstMatch(t) : null);
    final counted = _leadingQuantity.firstMatch(t);
    if (one != null) {
      quantity = '1';
      t = t.substring(one.end);
    } else if (padded != null) {
      // "03 PZ CONCHA", "02 KG TORTILLA", "02 X TACO": the same as "3 PZ
      // CONCHA" once the zeros are gone.
      final count = int.parse(padded[1]!);
      final plain = '$count${t.substring(padded[1]!.length)}';
      final unit = count > 0 ? _leadingQuantity.firstMatch(plain) : null;
      if (unit != null) {
        quantity = unit[2] == null ? '$count' : '$count ${unit[2]}';
        t = plain.substring(unit.end);
      } else {
        if (count > 0) quantity = '$count';
        t = t.substring(padded.end);
      }
    } else if (volume != null) {
      quantity = '${_plain(volume[1]!)} ${volume[2]}';
      t = t.substring(volume.end);
    } else if (coded != null) {
      quantity = coded[1];
      t = t.substring(coded[1]!.length).trim();
    } else if (figure != null) {
      quantity = figure[1];
      t = t.substring(figure.end);
    } else if (counted != null) {
      quantity = counted[2] == null
          ? _plain(counted[1]!)
          : '${_plain(counted[1]!)} ${counted[2]}';
      t = t.substring(counted.end);
    }
    t = t
        .trim()
        .replaceFirst(_leadingCode, '')
        .replaceFirst(_trailingCode, '')
        .replaceFirst(_unitPriceNote, '')
        .replaceFirst(_bracketFlag, '');
    return (t.replaceAll(_edges, '').trim(), quantity);
  }

  /// Wording that can be an item or a choice: mostly letters. Not a code
  /// ("ORDEN 100001/1 00002 7"), not a half-read rule or QR code
  /// ("XX*** X*****").
  static bool _looksLikeName(String name) {
    final letters = TextNormaliser.letterCount(name);
    return letters >= 3 &&
        RegExp(r'\d').allMatches(name).length <= letters &&
        RegExp(r'[^\sA-Za-z0-9À-ÿ]').allMatches(name).length <= letters;
  }

  /// A figure that is not a price because of the word before it:
  /// "CARRETERA MEXICO-TOLUCA KM 52.50", "FACTURA POS No. 12.345".
  static final RegExp _notAPrice = RegExp(
    r'(?:^|\s)(?:km|no|n[°º]|nro|num|ext)\.?$',
    caseSensitive: false,
  );

  /// A choice that says so itself: "- SIN CEBOLLA", "+ TOCINO", "> TERMINO
  /// MEDIO", "SIN HIELO", "CON LECHE", "EXTRA QUESO", "NO ONION".
  static final RegExp _marked = RegExp(
    r'^\s*(?:[-+>*»•]|(?:sin|con|extra|no|add|sub|with|without|sem|com)\b|'
    r'[cswCSW]/)',
    caseSensitive: false,
  );

  /// A name the printer broke after a joining word: "ENCHILADAS SUIZAS DE" /
  /// "POLLO CON QUESO".
  static final RegExp _joinsOn = RegExp(
    r'(?:\s(?:de|del|con|sin|y|al|en|la|las|los|el|with|and|of|com|da|do)|'
    r'\sc/|&)$',
    caseSensitive: false,
  );

  /// The second half of such a name: "DE POLLO", "DEL DIA".
  static final RegExp _carriesOn = RegExp(r'^del?\s', caseSensitive: false);

  static final RegExp _wordy = RegExp(r'[A-Za-z0-9À-ÿ]');

  /// A rule or a QR code half-read as letters ("XX*** X*****"): more marks
  /// than letters and figures.
  static bool _junk(String text) =>
      RegExp(r'[^\sA-Za-z0-9À-ÿ]').allMatches(text).length >
      TextNormaliser.letterCount(text) +
          RegExp(r'\d').allMatches(text).length;

  /// True for the totals block under the items (subtotal, tip, total) and
  /// for rows holding only numbers.
  static bool isSummaryRow(String row) {
    final text = _clean(row);
    if (text.isEmpty) return false;
    final parsed = _parse(text);
    return _summaryOf(text, parsed).$1 == _Summary.yes || parsed.figuresOnly;
  }

  /// A date or a time that OCR joined onto an item row from beside it
  /// ("15 NOV 2026  13:44:23  1 VACUNA").
  static const String _months =
      '(?:ene(?:ro)?|feb(?:rero|ruary)?|mar(?:zo|ch)?|abr(?:il)?|apr(?:il)?|'
      'may(?:o)?|jun(?:io|e)?|jul(?:io|y)?|ago(?:sto)?|aug(?:ust)?|'
      'sep(?:t|tiembre|tember)?|set(?:iembre)?|oct(?:ubre|ober)?|out|'
      'nov(?:iembre|ember)?|dic(?:iembre)?|dec(?:ember)?|dez|jan(?:uary)?|fev)';

  static final RegExp _dateOrTime = RegExp(
    // A month's name, whole or cut to three letters, then a year of two
    // or four figures: "2 MARGARITA 180.00" and "1 MAYONESA 390 G" are not
    // dates.
    '\\b\\d{1,2}[\\s/.\\-]+$_months\\.?'
    r"[\s/.\-'’]+(?:\d{4}|\d{2})\b(?![.,]\d)|"
    // In figures the same separator twice: "45.00 90.00" (a unit price and
    // its line total) is not a date.
    r'\b\d{1,2}\s?([/.\-])\s?\d{1,2}\s?\1\s?(?:\d{4}|\d{2})\b(?![.,]\d)|'
    // Year first: "2026-11-16".
    r'\b20\d{2}[/\-](?:0?[1-9]|1[0-2])[/\-](?:0?[1-9]|[12]\d|3[01])\b|'
    r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?[Mm]\.?)?',
    caseSensitive: false,
  );

  /// "Bs.S5.445,32", "Bs S10. 164,60", "MX$90.00", "Q45.00", "R$ 25,90": a
  /// currency written in front of a price, and a number OCR split at its
  /// separator.
  static final RegExp _currencyPrefix = RegExp(
    r'(?<![A-Za-z])(?:Bs\.?\s?S?\.?|MX\$|US\$|R\$|S/\.?|Q\.?)\s?(?=[0-9IlO])',
  );
  static final RegExp _splitNumber = RegExp(r'(\d)([.,])\s(\d{3}[.,]\d{2})\b');

  /// "129.00 MXN", "TOTAL MXN 70.00", "USD 4.50", "300.00 M.N.": the
  /// currency's code beside a price.
  static final RegExp _currencyCode = RegExp(
    r'(?<=\d)\s?(?:MXN|USD|GTQ|COP|VES|GBP|EUR|BRL|M\.N\.?)(?![A-Za-z])|'
    r'(?<![A-Za-z])(?:MXN|USD|GTQ|COP|VES|GBP|EUR|BRL)\s?(?=\$?\d)',
  );

  /// "$ 320.00": the sign read apart from its figure.
  static final RegExp _signApart = RegExp(r'([$£€])\s+(?=\d)');

  /// "45. 00", "25 .00": a space read inside the price at the end of a row.
  static final RegExp _splitDecimals =
      RegExp(r'(\d)(?:\s([.,])|([.,])\s)([\dOo]{2})$');

  /// "2 PAPAS FAM 190.0": some tills print prices with one decimal.
  static final RegExp _oneDecimalEnd = RegExp(r'(\s[$£€]?\d{1,6}[.,]\d)\s*$');

  /// "2 BANDEJA PAISA 64.000", "EMPANADA $3500": a price with no decimals.
  static final RegExp _wholeEnd =
      RegExp(r'(?:^|\s)(?:\$?\d{1,3}(?:[.,]\d{3})+|\$\d+)$');

  /// A price followed by one of the letters that could also be a size:
  /// "1.15 G", "$2.85 G", "1,250.00 G".
  static final RegExp _markedPrice = RegExp(
    r'(?:^|\s)[$£€]?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}\s([GKLM])$',
  );

  /// The receipt's own key to its tax letters: "G = GRAVADO  E = EXENTO".
  static final RegExp _flagLegend = RegExp(
    r'\b([GKLM])\s?=\s?(?:GRAV|EXEN|NO\s+SUJ|IVA|TASA)',
    caseSensitive: false,
  );

  /// "1 CAFE AMERICANO", "2 PAN DULCE": a row that begins with a quantity.
  /// Also "2 7UP" and "1 3 LECHES", whose names begin with a figure.
  static final RegExp _quantityStart =
      RegExp(r'^\d{1,3}\s+(?:\d\S*\s+)?\S*[A-Za-zÀ-ÿ]{2}');

  static String _clean(String row, [_Style style = const _Style()]) {
    var text = row
        .replaceAll(_dateOrTime, ' ')
        .replaceAll(_currencyPrefix, '')
        .replaceAll(_currencyCode, ' ')
        .replaceAllMapped(_signApart, (m) => m[1]!)
        .replaceAllMapped(_splitNumber, (m) => '${m[1]}${m[2]}${m[3]}')
        .trimRight()
        .replaceFirstMapped(
            _splitDecimals, (m) => '${m[1]}${m[2] ?? m[3]}${m[4]}');
    if (style.oneDecimal) {
      text = text.replaceFirstMapped(_oneDecimalEnd, (m) => '${m[1]}0');
    }
    return TextNormaliser.collapseSpaces(text);
  }

  /// How this receipt prints its figures. One decimal ("110.0"): at least
  /// two rows end that way, so it is the till's style and not a size ("AGUA
  /// 1.5") on one line. No decimals ("64.000", as in Colombia): no row has a
  /// price with two decimals and at least two end in thousands or in a
  /// figure with the peso sign.
  static _Style _styleOf(List<String> rows) {
    final oneDecimal =
        rows.where((r) => _oneDecimalEnd.hasMatch(r.trimRight())).length >= 2;
    var decimals = false;
    var whole = 0;
    var quantities = 0;
    for (final row in rows) {
      final text = _clean(row);
      if (text.split(' ').any((t) => _asAmount(t) != null)) decimals = true;
      if (_wholeEnd.hasMatch(text)) whole++;
      if (_quantityStart.hasMatch(text)) quantities++;
    }
    // A letter the receipt explains ("G = GRAVADO") is its tax mark. One
    // that could be a size is only tried as a mark by [extract], which
    // keeps that reading when the list then adds up to the printed total.
    final explained = <String>{};
    for (final row in rows) {
      for (final legend in _flagLegend.allMatches(row)) {
        explained.add(legend[1]!.toUpperCase());
      }
    }
    return _Style(
      oneDecimal: oneDecimal,
      wholePrices: !oneDecimal && !decimals && whole >= 2,
      quantityColumn: quantities >= 2,
      flags: explained.join(),
    );
  }

  /// "1,170.00" and "1.170,00" are 1170; on a receipt of whole prices
  /// "64.000" is 64000.
  static double? _value(String amount, _Style style) {
    var s = amount.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (style.wholePrices) {
      s = s.replaceAll(RegExp('[.,]'), '');
    } else if (s.length > 3) {
      final cut = s.length - 3;
      s = '${s.substring(0, cut).replaceAll(RegExp('[.,]'), '')}.'
          '${s.substring(cut + 1)}';
    }
    final value = double.tryParse(s);
    if (value == null) return null;
    return amount.contains('-') ? -value : value;
  }

  static double? _number(String quantity) =>
      double.tryParse(quantity.split(' ').first.replaceAll(',', '.'));

  /// Equal as money, give or take the rounding of a line ("2 x 10.164,60"
  /// printed as "20.329,21").
  static bool _close(double? a, double? b) =>
      a != null && b != null && (a - b).abs() <= 0.011 + b.abs() * 0.0005;

  static String _key(String name) =>
      TextNormaliser.collapseSpaces(name).toLowerCase();

  /// Finds the purchased items in OCR rows of a whole receipt or a crop:
  /// everything above the first priced line (address, customer, table, date)
  /// and everything from the subtotal down is ignored. Handles prices on the
  /// same row as the name and the two-row layout where the name sits above
  /// "1.00 x 2.21= 2.21E". Returns an empty list if no priced lines exist.
  static List<ReceiptItem> extract(List<String> rows) {
    final style = _styleOf(rows);
    final items = _extractWith(rows, style);
    // "1 CHURRASQUITO 35" / "1 CAFE 7" / "TOTAL Q55": whole prices with no
    // sign and no decimals anywhere. Read that way only when nothing else
    // was found and the lines then come to the printed total.
    if (items.isEmpty && !rows.any(_decimalFigure.hasMatch)) {
      final bare = style.copyWith(bareWhole: true);
      final whole = _extractWith(rows, bare);
      final printed = _printedTotals(rows, bare);
      if (whole.length >= 2 && _addsUp(whole, printed, bare)) return whole;
      return items;
    }
    final totals = _printedTotals(rows, style);
    if (totals.isEmpty || _addsUp(items, totals, style)) return items;
    // The list does not come to a printed total. Two things on a receipt
    // can be read two ways; the other reading is kept only when the list
    // then does add up.
    // - "1.15 G", "2.85 G": a letter after the last price that could be a
    //   size (grams, kilos, litres, metres) or this till's tax mark.
    //   Otherwise "AGUA 1.50 L" keeps its size.
    // - "DUFRY" / "2 X 19.00" / "TOBLERONE 38.00": a quantity row that
    //   could belong to the wording above it or to the item under it.
    final letters = <String>{};
    for (final row in rows) {
      final m = _markedPrice.firstMatch(_clean(row, style));
      if (m != null && !style.flags.contains(m[1]!)) letters.add(m[1]!);
    }
    final marked = style.copyWith(flags: style.flags + letters.join());
    for (final other in [
      if (letters.isNotEmpty) marked,
      style.copyWith(quantityAbove: true),
      if (letters.isNotEmpty) marked.copyWith(quantityAbove: true),
    ]) {
      final read = _extractWith(rows, other);
      if (_addsUp(read, totals, other)) return read;
    }
    return items;
  }

  static final RegExp _decimalFigure = RegExp(r'\d[.,]\d{2}(?!\d)');

  /// The amounts on the subtotal and total rows.
  static List<double> _printedTotals(List<String> rows, _Style style) {
    final totals = <double>[];
    for (final raw in rows) {
      final text = _clean(raw, style);
      final row = _parse(text, style);
      final kind = _summaryOf(text, row);
      if (kind.$1 != _Summary.yes || !kind.$2 || row.amount == null) continue;
      final value = _value(row.amount!, style);
      if (value != null && value > 0) totals.add(value);
    }
    return totals;
  }

  /// Whether the priced lines come to one of the printed totals.
  static bool _addsUp(
    List<ReceiptItem> items,
    List<double> totals,
    _Style style,
  ) {
    var sum = 0.0;
    var priced = 0;
    for (final item in items) {
      final value =
          item.amountText == null ? null : _value(item.amountText!, style);
      if (value == null) continue;
      sum += value;
      priced++;
    }
    return priced > 0 && totals.any((total) => _close(sum, total));
  }

  static List<ReceiptItem> _extractWith(List<String> rows, _Style style) {
    final n = rows.length;
    final texts = [for (final r in rows) _clean(r, style)];
    final parsed = [for (final t in texts) _parse(t, style)];
    final kinds = [for (var i = 0; i < n; i++) _summaryOf(texts[i], parsed[i])];
    for (var i = 0; i < n; i++) {
      if (kinds[i].$1 != _Summary.yes &&
          _datedRow.hasMatch(rows[i]) &&
          _taxWord.hasMatch(texts[i])) {
        kinds[i] = (_Summary.yes, false);
      }
    }
    // Whether, under each row, the totals are still to come, and whether
    // anything of the totals block is.
    final totalsBelow = List<bool>.filled(n, false);
    final summaryBelow = List<bool>.filled(n, false);
    for (var i = n - 2; i >= 0; i--) {
      final yes = kinds[i + 1].$1 == _Summary.yes;
      totalsBelow[i] = totalsBelow[i + 1] || (yes && kinds[i + 1].$2);
      summaryBelow[i] = summaryBelow[i + 1] || yes;
    }
    // A product that opens with a totals word ("TABLE WATER 0.00") is an
    // item while the totals are still under it, or when the rows hold no
    // totals at all (a crop of the items). Lower down it is a payment row
    // with a name the list does not know ("TARJETA BANCO EJEMPLO 300.00").
    bool summary(int i) =>
        kinds[i].$1 == _Summary.yes ||
        (kinds[i].$1 == _Summary.product && !totalsBelow[i] && summaryBelow[i]);
    bool voidMarker(int i) {
      final m = _void.firstMatch(parsed[i].head);
      return m != null &&
          parsed[i].amount == null &&
          TextNormaliser.letterCount(parsed[i].head.substring(m.end)) < 3;
    }

    // A folio prints the day before every charge ("16/11/26 HABITACION
    // 2,150.00"), and the tax on it and the payments the same way. With two
    // dated charges the rows are a folio: tax rows and day totals between
    // its dated rows are passed over and do not end the list, dated
    // payments are not items, and once the last dated row is a payment only
    // totals and breakdowns follow.
    final dated = [for (final r in rows) _datedRow.hasMatch(r)];
    // What the dated charges come to, and the dated tax on them.
    var datedSum = 0.0;
    var datedTax = 0.0;
    for (var k = 0; k < n; k++) {
      final amount = parsed[k].amount;
      if (!dated[k] || amount == null) continue;
      final value = _value(amount, style);
      if (value == null || value <= 0) continue;
      if (_cardPayment.hasMatch(texts[k]) || _folioPayment.hasMatch(texts[k])) {
        continue;
      }
      if (kinds[k].$1 != _Summary.yes) {
        datedSum += value;
      } else if (!kinds[k].$2) {
        datedTax += value;
      }
    }
    bool payment(int k) {
      final amount = parsed[k].amount;
      if (!dated[k] || amount == null) return false;
      if (kinds[k].$1 == _Summary.yes || _cardPayment.hasMatch(texts[k])) {
        return true;
      }
      if (!_folioPayment.hasMatch(texts[k])) return false;
      final value = _value(amount, style);
      return amount.startsWith('-') ||
          _close(value, datedSum) ||
          _close(value, datedSum + datedTax);
    }
    var datedCharges = 0;
    var undatedCharges = 0;
    var lastDated = -1;
    for (var k = 0; k < n; k++) {
      final amount = parsed[k].amount;
      if (amount == null) continue;
      final charge = kinds[k].$1 != _Summary.yes &&
          !amount.startsWith('-') &&
          parsed[k].head.isNotEmpty;
      if (!dated[k]) {
        if (charge) undatedCharges++;
        continue;
      }
      lastDated = k;
      if (charge && !payment(k)) datedCharges++;
    }
    final folio = datedCharges >= 2 && datedCharges >= undatedCharges;
    final settled = folio && payment(lastDated);
    // A folio with a running balance in its last column ("HABITACION
    // 1,500.00 3,240.00"): each balance is the one above plus the charge.
    var balances = 0;
    double? balance;
    for (var k = 0; k < n; k++) {
      final amounts = parsed[k].amounts;
      if (!dated[k] || amounts.length < 2) continue;
      final charge = _value(amounts[amounts.length - 2], style);
      final after = _value(amounts.last, style);
      if (charge != null && _close((balance ?? 0) + charge, after)) balances++;
      balance = after;
    }
    final balanceColumn = folio && balances >= 2;
    String? amountOf(int k) {
      final amounts = parsed[k].amounts;
      return balanceColumn && dated[k] && amounts.length >= 2
          ? amounts[amounts.length - 2]
          : parsed[k].amount;
    }

    // The printed totals, the tax passed over on a folio, and whether the
    // lines found so far already come to a total (with or without that tax).
    final totals = <double>[
      for (var k = 0; k < n; k++)
        if (kinds[k].$1 == _Summary.yes && kinds[k].$2 && parsed[k].amount != null)
          _value(parsed[k].amount!, style) ?? 0,
    ];
    var taxSum = 0.0;
    final folds = [
      for (final text in texts) _fold(text).replaceFirst(_leadIn, ''),
    ];
    bool passOver(int k) =>
        _levy.hasMatch(folds[k]) ||
        _count.hasMatch(folds[k]) ||
        _lodgingTax.hasMatch(texts[k]) ||
        _numberedTax.hasMatch(texts[k]) ||
        _ratedTax.hasMatch(texts[k]);
    // The number a count row gives ("TOTAL ARTICULOS 6").
    int? counted;
    for (var k = 0; k < n && counted == null; k++) {
      if (!_count.hasMatch(folds[k])) continue;
      final figures = RegExp(r'\d+').allMatches(folds[k]).toList();
      if (figures.isNotEmpty) counted = int.tryParse(figures.last[0]!);
    }
    // Rows that read as a priced item at first sight, and how many of
    // them open with a number.
    var itemRows = 0;
    var leadItemRows = 0;
    for (var k = 0; k < n; k++) {
      // Down to the subtotal or total: what is printed under it ("DESCUENTO
      // 3.60", payments) is not part of the list.
      if (itemRows > 0 && kinds[k].$1 == _Summary.yes && kinds[k].$2) break;
      // A discount row ("DESC. 10% -3.60") has no number in front on any
      // till; it says nothing about the column.
      if (parsed[k].amount != null &&
          !parsed[k].amount!.startsWith('-') &&
          parsed[k].head.isNotEmpty &&
          kinds[k].$1 != _Summary.yes) {
        itemRows++;
        if (_nameOf(parsed[k].head, style).$2 != null) leadItemRows++;
      }
    }

    // Whether rows numbered in front carry their quantity after the name
    // ("1 TACO PASTOR 2 22.00 44.00"): every such row multiplies out with
    // the number after the name, and at least one does not with the number
    // in front.
    var withLead = 0;
    var byTrailing = 0;
    var notByLead = 0;
    for (var k = 0; k < n; k++) {
      final row = parsed[k];
      if (row.amount == null ||
          row.head.isEmpty ||
          row.quantity != null ||
          row.amounts.length < 2 ||
          kinds[k].$1 == _Summary.yes ||
          _leadKind(row.head) != _LeadKind.plain) {
        continue;
      }
      final (name, lead) = _nameOf(row.head, style);
      if (lead == null) continue;
      withLead++;
      final measured = _measured(name, row.amounts, row.amount!, style);
      if (measured == null) continue;
      byTrailing++;
      final count = _number(lead);
      if (count == null ||
          !_close(measured.$3 * count, _value(row.amount!, style))) {
        notByLead++;
      }
    }
    final table = withLead >= 2 && byTrailing == withLead && notByLead >= 1;
    // How many rows write "x2" as a word among their figures.
    final timesRows = parsed.where((row) => row.times != null).length;
    // A number in front that multiplies out with the unit price is a
    // quantity, whatever the numbers of the other rows look like.
    var codedMultiplies = false;
    var paddedMultiplies = false;

    // A quantity row ("2 x 5.50") whose sum is the price of the row under
    // it. Not a row that breaks off ("1.00 x 2.21="): its total was read
    // onto the next row, and it belongs to the name above.
    bool fitsBelow(int j) {
      if (j + 1 >= n || !parsed[j].figuresOnly || !parsed[j].complete) {
        return false;
      }
      final count =
          parsed[j].quantity == null ? null : _number(parsed[j].quantity!);
      final each =
          parsed[j].amount == null ? null : _value(parsed[j].amount!, style);
      final under = parsed[j + 1];
      return count != null &&
          each != null &&
          !summary(j + 1) &&
          under.head.isNotEmpty &&
          under.amount != null &&
          _close(count * each, _value(under.amount!, style));
    }

    var quantityRows = 0;
    var fitting = 0;
    var noWordingAbove = false;
    for (var j = 0; j < n; j++) {
      final row = parsed[j];
      if (!row.figuresOnly || !row.complete || row.quantity == null) continue;
      quantityRows++;
      if (!fitsBelow(j)) continue;
      fitting++;
      if (j == 0 || parsed[j - 1].amount != null || parsed[j - 1].head.isEmpty) {
        noWordingAbove = true;
      }
    }
    final quantityRowsAbove =
        quantityRows >= 2 && fitting == quantityRows && noWordingAbove;

    final items = <ReceiptItem>[];
    // The number each item's row opened with, by the item's first row, and
    // the same for every priced row in order, voided ones too.
    final leads = <int, _Lead>{};
    final leadRows = <_Lead>[];
    // For each item whose quantity stood after its name ("x2", "2 22.00
    // 44.00"), the number in front of the name, if any.
    final behind = <bool>[];
    bool paidUp() {
      var sum = 0.0;
      var priced = 0;
      for (final item in items) {
        final value =
            item.amountText == null ? null : _value(item.amountText!, style);
        if (value == null) continue;
        sum += value;
        priced++;
      }
      return priced > 0 &&
          totals.any((t) => t > 0 && (_close(sum, t) || _close(sum + taxSum, t)));
    }

    // "AHORRO CAFE NESCAFE -12.00", "AHORRO 2X1 -89.00" with the next
    // item right under it: a saving printed in the list. Before the totals
    // ("AHORRO EN ESTA COMPRA -5.00" / "TOTAL") it is part of them.
    bool savingOnItem(int i) {
      final amount = parsed[i].amount;
      if (items.isEmpty || amount == null || !amount.startsWith('-')) {
        return false;
      }
      if (!_savingOn.hasMatch(_fold(texts[i]).replaceFirst(_leadIn, ''))) {
        return false;
      }
      var k = i + 1;
      while (k < n && !_wordy.hasMatch(texts[k])) {
        k++;
      }
      if (k >= n || summary(k)) return false;
      final next = parsed[k];
      return next.head.isNotEmpty &&
          next.amount != null &&
          !next.amount!.startsWith('-');
    }

    // Quantities printed on the row above their item ("2 x Bs 120,00").
    final quantityAbove = <int, String>{};
    var started = false;
    // Name rows with no price, right above the current row, that became
    // neither items nor choices.
    var loose = 0;
    var voidAbove = false;
    var i = 0;
    while (i < n) {
      final text = texts[i];
      if (!_wordy.hasMatch(text) || _heading.hasMatch(text)) {
        i++;
        continue;
      }
      // Under the last dated row of a folio that is paid, or whose charges
      // already come to its total, only totals and breakdowns follow.
      if (folio && i > lastDated && (settled || paidUp())) break;
      if (_zeroDiscount.hasMatch(folds[i])) {
        i++;
        continue;
      }
      if (summary(i) && !savingOnItem(i)) {
        if (folio && i < lastDated) {
          final amount = amountOf(i);
          final value = amount == null ? null : _value(amount, style);
          if (value != null &&
              value > 0 &&
              !kinds[i].$2 &&
              !_cardPayment.hasMatch(text) &&
              !_folioPayment.hasMatch(text)) {
            taxSum += value;
          }
          i++;
          continue;
        }
        if (passOver(i)) {
          i++;
          continue;
        }
        if (started) break;
        loose = 0;
        i++;
        continue;
      }
      if (voidMarker(i)) {
        voidAbove = true;
        i++;
        continue;
      }
      // "1 Servicio 2 Hospedaje habitacion sencilla 732.00 0.00 1,464.00 IVA
      // 156.86": number, goods or service, quantity, description, unit
      // price, discount, total, tax.
      final invoiced = _invoiceRow.firstMatch(text);
      if (invoiced != null) {
        started = true;
        items.add(ReceiptItem(
          description: invoiced[2]!.trim(),
          quantity: _plain(invoiced[1]!),
          amountText: invoiced[3],
          firstRow: i,
          lastRow: i,
        ));
        loose = 0;
        voidAbove = false;
        i++;
        continue;
      }
      final row = parsed[i];

      if (row.figuresOnly) {
        final quantity = row.quantity == null ? null : _number(row.quantity!);
        final amount = row.amount == null ? null : _value(row.amount!, style);
        if (quantity != null && amount != null) {
          final above = items.isEmpty ? null : items.last;
          final below = i + 1 < n ? parsed[i + 1] : null;
          if (above != null &&
              above.lastRow == i - 1 &&
              above.amountText != null &&
              above.quantity == null &&
              _close(_value(above.amountText!, style)! * quantity, amount)) {
            // "DOUBLE PEPPERONI 10.164,60" / "x2 20.329,21": how many, and
            // the line total, on the row under the item.
            items[items.length - 1] = ReceiptItem(
              description: above.description,
              quantity: row.quantity,
              amountText: row.amount,
              firstRow: above.firstRow,
              lastRow: i,
            );
          } else if (below != null &&
              below.head.isNotEmpty &&
              below.amount != null &&
              _close(quantity * amount, _value(below.amount!, style))) {
            // "2 x Bs 120,00" / "AREPA REINA PEPIADA (G) Bs 240,00": how
            // many and the unit price on the row above the item.
            quantityAbove[i + 1] = row.quantity!;
          }
        }
        loose = 0;
        i++;
        continue;
      }

      if (row.amount != null) {
        final voided = _void.firstMatch(row.head);
        final head = voided == null ? row.head : row.head.substring(voided.end);
        final (rawName, leading) = _nameOf(head, style);
        var name = rawName;
        // A labelled field ("PRECIO: $23.99", "TARIFA: $40.00") is not an
        // item, nor is a figure after "KM" or "No.".
        final field = row.head.trimRight().endsWith(':') ||
            _notAPrice.hasMatch(row.head.trimRight());
        if (field || TextNormaliser.letterCount(name) < 2) {
          loose = 0;
          voidAbove = false;
          i++;
          continue;
        }
        final kind = _leadKind(head);
        if (leading != null) leadRows.add(_Lead(leading, kind));
        var amountText = amountOf(i)!;
        var last = i;
        // "PEPSI 1.815,11 X" / "5.445,32": the line total on the next row.
        if (!row.complete && i + 1 < n) {
          final under = parsed[i + 1];
          if (under.figuresOnly && under.amount != null) {
            amountText = under.amount!;
            last = i + 1;
          }
        }
        final negative = amountText.startsWith('-');
        if (voided != null || voidAbove || negative) {
          // "1 CERVEZA 55.00" … "CANCELADO 1 CERVEZA -55.00", or "** VOID
          // **" / "MUFFIN 3.25-": the line and the one it takes back both go.
          final absolute = amountText.replaceFirst('-', '');
          final at = !negative
              ? -1
              : items.lastIndexWhere((item) =>
                  item.amountText == absolute &&
                  _key(item.description) == _key(name));
          if (at >= 0) {
            var until = at + 1;
            while (until < items.length && items[until].amountText == null) {
              until++;
            }
            items.removeRange(at, until);
          }
          if (at >= 0 || voided != null || (voidAbove && negative)) {
            loose = 0;
            voidAbove = false;
            i = last + 1;
            continue;
          }
        }
        // On a folio a dated payment ("17/11/26 PREPAGO AGENCIA
        // -1,988.00", "18/11/26 TC VISA 4,300.00") is not something bought.
        // A dated discount or correction is a line like any other.
        if (folio && payment(i)) {
          loose = 0;
          voidAbove = false;
          i = last + 1;
          continue;
        }
        final total = _value(amountText, style);
        final count = leading == null ? null : _number(leading);
        final unit = row.amounts.length >= 2
            ? _value(row.amounts[row.amounts.length - 2], style)
            : null;
        if (count != null &&
            count > 1 &&
            unit != null &&
            unit > 0 &&
            _close(unit * count, total)) {
          if (kind == _LeadKind.coded) codedMultiplies = true;
          if (kind == _LeadKind.padded) paddedMultiplies = true;
        }
        var quantity = row.quantity ?? quantityAbove[i];
        // "1 2 TACO PASTOR 22.00 44.00": the number of the line, then how
        // many, when only the second gives the total.
        var numberedLine = false;
        if (quantity == null &&
            kind == _LeadKind.plain &&
            count != null &&
            unit != null &&
            unit > 0 &&
            !_close(unit * count, total)) {
          final inner = _innerQuantity.firstMatch(name);
          final many =
              inner == null ? null : _number(inner[1]!.replaceAll(',', '.'));
          if (inner != null && many != null && _close(unit * many, total)) {
            quantity = _plain(inner[1]!);
            name = name.substring(inner.end);
            numberedLine = true;
          }
        }
        if (row.times != null && quantity == row.quantity) {
          // "x2" after the name is how many; "X6" is a pack size when the
          // row's own sum says so ("2 CERVEZA CORONA X6 159.00 318.00"). With
          // no unit price it is one after a number and a barcode ("4
          // 7707654300019 JABON PROTEX X3 9.800"), and after a quantity in
          // front when every row opens with one and others carry no "x"
          // ("1 CUBETA CORONA X6 330.00" beside "3 CERVEZA 165.00"; not "12
          // ALITAS BBQ x2" beside "PAPAS GAJO").
          final times = double.parse(row.quantity!);
          final pack = unit != null && unit > 0
              ? !_close(unit * times, total) &&
                  count != null &&
                  _close(unit * count, total)
              : times >= 2 &&
                  (kind == _LeadKind.coded ||
                      (kind == _LeadKind.plain &&
                          leading != null &&
                          timesRows < itemRows &&
                          leadItemRows == itemRows));
          if (pack) {
            name = '$name ${row.times}';
            quantity = null;
          }
        }
        // The quantity stood after the name, not in front of it.
        var after = quantity != null;
        var used = false;
        if (quantity == null) {
          // "TACO AL PASTOR 2 22.00 44.00": name, quantity, unit price and
          // line total, where 2 x 22.00 is 44.00. When the number in front
          // already gives the total ("2 COCA COLA 2 L 30.00 60.00", "1 COMBO
          // 1 89.00 89.00") the one after the name belongs to the name,
          // unless the whole list is numbered in front.
          final measured = _measured(name, row.amounts, amountText, style);
          final byLead = measured != null &&
              count != null &&
              _close(measured.$3 * count, total);
          if (measured != null && (!byLead || table)) {
            quantity = measured.$1;
            name = measured.$2;
            after = true;
          } else {
            quantity = leading;
            used = leading != null;
          }
        }
        // With the quantity after the name, a number in front repeats it
        // ("2 CERVEZA 2 x 55.00"), belongs to the name ("12 ALITAS BBQ x2",
        // "3 LECHES x2") or is a line number or a code ("1 TACO PASTOR x2",
        // "104 SOPA"); which of the last two, the whole list tells further
        // down.
        var kept = false;
        if (after) {
          final plain = leading != null && kind == _LeadKind.plain;
          final same = count != null && _number(quantity!) == count;
          behind.add(leading != null);
          if (plain && leading != '1' && !same && !numberedLine) {
            name = '$leading $name';
            kept = true;
          }
        }
        started = true;
        items.add(ReceiptItem(
          description: name,
          quantity: quantity,
          amountText: amountText,
          firstRow: quantityAbove.containsKey(i) ? i - 1 : i,
          lastRow: last,
        ));
        if (leading != null) {
          leads[items.last.firstRow] =
              _Lead(leading, kind, used: used, kept: kept);
        }
        loose = 0;
        voidAbove = false;
        i = last + 1;
        continue;
      }

      final (name, leading) = _nameOf(row.head, style);
      if (!row.head.contains(':') && !_junk(text) && _looksLikeName(name)) {
        var j = i + 1;
        while (j < n && texts[j].isEmpty) {
          j++;
        }
        // "TIQUETE 0045120" / "2 x 5.50" / "SOPA DE TORTILLA 11.00": a
        // quantity row whose sum is the price of the row under it belongs to
        // that row, not to the wording above.
        // Either every such row of the receipt fits the row under it and
        // one of them has no wording above (the till prints them that way),
        // or the wording above holds a long number, as no product does. A
        // lone "1 x $39.00" between a product and a fee of the same amount
        // stays with the product.
        final below = j < n &&
            fitsBelow(j) &&
            (style.quantityAbove ||
                quantityRowsAbove ||
                RegExp(r'\d{4,}').hasMatch(row.head));
        if (j < n && parsed[j].figuresOnly && !below) {
          final figures = parsed[j];
          var amountText = figures.amount;
          var last = j;
          var j2 = j + 1;
          while (j2 < n && texts[j2].isEmpty) {
            j2++;
          }
          final under = j2 < n && parsed[j2].figuresOnly ? parsed[j2] : null;
          var unsure = false;
          if (under != null && under.amount != null && under.quantity == null) {
            final quantity =
                figures.quantity == null ? null : _number(figures.quantity!);
            final unit =
                figures.amount == null ? null : _value(figures.amount!, style);
            if (!figures.complete ||
                (quantity != null &&
                    figures.amounts.length == 1 &&
                    _close(quantity * (unit ?? 0),
                        _value(under.amount!, style)))) {
              // "1.00 x 12.35=" / "12.35E", "2 x 55.00" / "110.00": the
              // line total printed on the row under the sum.
              amountText = under.amount;
              last = j2;
            } else if (loose > 0 && figures.quantity == null) {
              // Several names, then several bare prices: the columns were
              // read apart and which price is whose cannot be told.
              unsure = true;
            }
          }
          if (amountText != null && !unsure) {
            started = true;
            items.add(ReceiptItem(
              description: name,
              // A unit price read on the name row is not a quantity.
              quantity: figures.quantity ?? (row.tail.isEmpty ? leading : null),
              amountText: amountText,
              firstRow: i,
              lastRow: last,
            ));
            if (leading != null) {
              final lead = _Lead(
                leading,
                _leadKind(row.head),
                used: figures.quantity == null && row.tail.isEmpty,
              );
              leads[i] = lead;
              leadRows.add(lead);
            }
            loose = 0;
            voidAbove = false;
            i = last + 1;
            continue;
          }
        }
        if (started &&
            row.tail.isEmpty &&
            items.isNotEmpty &&
            items.last.lastRow == i - 1) {
          final previous = items.last;
          if (previous.amountText != null &&
              !RegExp(r'^\s*[-+>*»•]').hasMatch(text) &&
              (_joinsOn.hasMatch(previous.description) ||
                  _carriesOn.hasMatch(name))) {
            items[items.length - 1] = ReceiptItem(
              description: '${previous.description} $name',
              quantity: previous.quantity,
              amountText: previous.amountText,
              firstRow: previous.firstRow,
              lastRow: i,
            );
            i++;
            continue;
          }
          // Lines with no price under an item are choices for it ("VASO
          // DESECHABLE", "CAMBIO L. LIGHT" under a milkshake). The run must
          // sit right under an item and end at another item, the totals or
          // the end of the rows.
          // "12 PIEZAS", "10 PIEZAS BBQ" under a dish say how many
          // pieces: the number stays.
          String note(String name, _Row row) {
            final printed = row.head.replaceAll(_edges, '').trim();
            return _unitToken.hasMatch(name) || _pieces.hasMatch(printed)
                ? printed
                : name;
          }
          final choices = <(int, String)>[(i, note(name, row))];
          // Plain lines are counted: a long run of them is a footer, not
          // choices. Marked ones ("- SIN CEBOLLA") are not.
          var plain = _marked.hasMatch(text) ? 0 : 1;
          var k = i + 1;
          var accepted = false;
          while (true) {
            if (k >= n) {
              accepted = true;
              break;
            }
            final next = texts[k];
            // A rule ("-----") or blank between the items and the totals.
            if (!_wordy.hasMatch(next)) {
              k++;
              continue;
            }
            if (summary(k)) {
              accepted = true;
              break;
            }
            // A heading, a "** VOID **" marker, a half-read QR code.
            if (_heading.hasMatch(next) || voidMarker(k) || _junk(next)) {
              k++;
              continue;
            }
            final nextRow = parsed[k];
            if (nextRow.head.isNotEmpty && nextRow.amount != null) {
              accepted = true; // the next priced item
              break;
            }
            final (nextName, _) = _nameOf(nextRow.head, style);
            if (nextRow.tail.isNotEmpty ||
                nextRow.head.contains(':') ||
                !_looksLikeName(nextName)) {
              break;
            }
            // A name whose price is on the row under it is the next item.
            if (k + 1 < n &&
                parsed[k + 1].figuresOnly &&
                parsed[k + 1].amount != null) {
              accepted = true;
              break;
            }
            if (!_marked.hasMatch(next)) {
              if (plain >= 4) break;
              plain++;
            }
            choices.add((k, note(nextName, nextRow)));
            k++;
          }
          if (accepted) {
            for (final (at, choice) in choices) {
              items.add(
                ReceiptItem(description: choice, firstRow: at, lastRow: at),
              );
            }
            i = choices.last.$1 + 1;
            continue;
          }
        }
        loose++;
        i++;
        continue;
      }
      loose = 0;
      i++;
    }
    if (items.isEmpty) {
      final paired = _pairedBlocks(texts, parsed, summary, style);
      return paired.isNotEmpty ? paired : _labelled(texts, parsed, style);
    }
    // Numbers in front of barcodes that climb from one, row after row ("1
    // 7702001012345 AGUA", "2 7702004098765 PAN", "3 …"), number the lines;
    // a voided line or a misread row may leave one gap.
    final coded = [
      for (final lead in leadRows)
        if (lead.kind == _LeadKind.coded) int.tryParse(lead.text) ?? -1,
    ];
    // Only when the receipt's own count of things bought says so: it then
    // gives no more than the number of rows, not the sum of those numbers.
    // Without it, "1", "2", "3" before barcodes stay quantities.
    bool countSays(List<int> numbers) =>
        counted != null &&
        counted <= numbers.length &&
        counted != numbers.fold<int>(0, (a, b) => a + b);
    // Four rows or more numbered 1, 2, 3, 4 with none missing are not
    // quantities by chance.
    var straight = coded.length >= 4;
    for (var k = 0; straight && k < coded.length; k++) {
      straight = coded[k] == k + 1;
    }
    final numbered = !codedMultiplies &&
        _countsUp(coded) &&
        (straight || countSays(coded));
    // "001", "002", "003": zeros in front and counting up, the same, when
    // the count of things bought says so or the quantities stand elsewhere
    // on every row. "01", "02", "03" with nothing else to go by are
    // quantities, and so are "002" then "001".
    final padded = [
      for (final lead in leadRows)
        if (lead.kind == _LeadKind.padded) int.tryParse(lead.text) ?? -1,
    ];
    final counters = !paddedMultiplies &&
        padded.isNotEmpty &&
        padded.first == 1 &&
        _countsUp(padded) &&
        (countSays(padded) ||
            !leads.values.any((l) => l.kind == _LeadKind.padded && l.used));
    // A short code after every such counter is the product's code.
    final codeColumn = counters &&
        items.every((item) =>
            leads[item.firstRow]?.kind != _LeadKind.padded ||
            _shortCode.hasMatch(item.description));
    // A number in front of every row whose quantity stands after the name
    // is a column of line numbers or codes; in front of only some, it
    // belongs to those names.
    // Rows with no number in front at all say there is no such column.
    final lines = !behind.contains(false) && leadItemRows == itemRows;
    // "01 2 TACO DE RIB EYE 190.00", "02 1 QUESO FUNDIDO 125.00": after
    // every counter a second number, which is how many.
    final counterThenQuantity = padded.length >= 2 &&
        padded.first == 1 &&
        _countsUp(padded) &&
        items.every((item) =>
            leads[item.firstRow]?.kind != _LeadKind.padded ||
            RegExp(r'^\d{1,3}\s+(?=\S*[A-Za-zÀ-ÿ])')
                .hasMatch(item.description));
    for (var k = 0; k < items.length; k++) {
      final item = items[k];
      final lead = leads[item.firstRow];
      if (lead == null) continue;
      var description = item.description;
      var quantity = item.quantity;
      if (counterThenQuantity && lead.kind == _LeadKind.padded && lead.used) {
        final space = description.indexOf(' ');
        quantity = description.substring(0, space);
        description = description.substring(space).trim();
      }
      if (lead.used &&
          ((numbered && lead.kind == _LeadKind.coded) ||
              (counters && lead.kind == _LeadKind.padded))) {
        quantity = null;
      }
      if (codeColumn && lead.kind == _LeadKind.padded) {
        description = description.replaceFirst(_shortCode, '');
      }
      if (lines && lead.kept && description.startsWith('${lead.text} ')) {
        description = description.substring(lead.text.length + 1);
      }
      if (description != item.description || quantity != item.quantity) {
        items[k] = ReceiptItem(
          description: description,
          quantity: quantity,
          amountText: item.amountText,
          firstRow: item.firstRow,
          lastRow: item.lastRow,
        );
      }
    }
    return items;
  }

  static final RegExp _innerQuantity =
      RegExp(r'^(\d{1,3}(?:[.,]\d{1,3})?)\s+(?=\S*[A-Za-zÀ-ÿ])');

  /// Numbers that count up from one, row after row; in three rows or more
  /// one may be missing (a voided line, a row OCR lost).
  static bool _countsUp(List<int> list) {
    if (list.length < 2) return false;
    if (list.length == 2) return list[0] == 1 && list[1] == 2;
    if (list.first < 1 || list.first > 2 || list.last > list.length + 1) {
      return false;
    }
    for (var k = 1; k < list.length; k++) {
      if (list[k] <= list[k - 1]) return false;
    }
    return true;
  }

  static _LeadKind _leadKind(String head) {
    final t = head.replaceAll(_edges, '').trim();
    // "001 7501055300075 COCA COLA": zeros in front and then a barcode count
    // with the numbers before barcodes.
    if (_quantityThenCode.hasMatch(t)) return _LeadKind.coded;
    if (_padded.hasMatch(t)) return _LeadKind.padded;
    return _LeadKind.plain;
  }

  static final RegExp _quantityWord =
      RegExp(r'^(?:[1-9]\d{0,2}|\d{1,3}[.,]\d{1,3})$');

  /// The quantity printed after the name, before the unit price and the
  /// line total: "TACO AL PASTOR 2 22.00 44.00", "SUPER 8.524 31.49 268.42";
  /// with its unit, "MAGNA 35.214 LTS 23.99 844.78"; with a discount column,
  /// "SUPER 8.524 31.49 0.00 268.42"; with a unit price of three decimals,
  /// "UNLEADED 8.524 3.459 29.48". Only when quantity times unit price is
  /// the total. Returns the quantity, the name without it, the unit price.
  static (String, String, double)? _measured(
    String name,
    List<String> amounts,
    String total,
    _Style style,
  ) {
    final words = name.split(' ');
    final sum = _value(total, style);
    if (sum == null) return null;
    double? number(String word) => _quantityWord.hasMatch(word)
        ? double.parse(word.replaceAll(',', '.'))
        : null;
    final count = words.length >= 2 ? number(words.last) : null;
    double? unit;
    if (amounts.length >= 2) {
      unit = _value(amounts[amounts.length - 2], style);
      if (amounts.length >= 3) {
        final before = _value(amounts[amounts.length - 3], style);
        if (unit == 0) {
          // A discount column with nothing in it.
          unit = before;
        } else if (count != null &&
            before != null &&
            unit != null &&
            count > 0 &&
            _close(before * count - unit, sum)) {
          // "PARACETAMOL 2 45.00 9.00 81.00": 2 x 45.00 less 9.00.
          return (
            _plain(words.last),
            words.take(words.length - 1).join(' '),
            before,
          );
        }
      }
    }
    // A free item has a unit price of nothing ("SANGRITA 2 0.00 0.00"); a
    // promotion or a return has one below nothing ("PROMO 1 -9.50 -9.50").
    if (unit != null && (unit != 0 || sum == 0)) {
      if (count != null && count > 0 && _close(unit * count, sum)) {
        return (
          _plain(words.last),
          words.take(words.length - 1).join(' '),
          unit,
        );
      }
      // A measure with its decimals: "0.250 KG", "8.524 GAL". "2 L" after
      // a name is the size of the bottle.
      if (words.length >= 3 && _measureUnit.hasMatch(words.last)) {
        final figure = words[words.length - 2];
        final measure = figure.contains(RegExp('[.,]')) ? number(figure) : null;
        if (measure != null && measure > 0 && _close(unit * measure, sum)) {
          return (
            '${_plain(figure)} ${words.last}',
            words.take(words.length - 2).join(' '),
            unit,
          );
        }
      }
    }
    if (amounts.length == 1 && words.length >= 3) {
      final figure = words[words.length - 2];
      final measure = number(figure);
      final price = number(words.last);
      // Both as a pump prints them, with three decimals: "8.524 3.459".
      // "549.00 0.250" is a price for each kilo and a weight.
      final pump = RegExp(r'[.,]\d{3}$');
      if (measure != null &&
          price != null &&
          measure > 0 &&
          pump.hasMatch(figure) &&
          pump.hasMatch(words.last) &&
          _close(measure * price, sum)) {
        return (_plain(figure), words.take(words.length - 2).join(' '), price);
      }
    }
    return null;
  }

  /// A line of a Guatemalan electronic invoice (FEL) in the tax office's
  /// layout: "#No", "B/S" (Bien or Servicio), quantity, description, unit
  /// price, discounts, total and, for some, the tax.
  static final RegExp _invoiceRow = RegExp(
    r'^\d{1,3}\s+(?:bien|servicio)\s+(\d{1,4}(?:[.,]\d{1,2})?)\s+(.+?)\s+'
    r'(?:\d{1,3}(?:[.,]\d{3})*[.,]\d{2})\s+(?:\d{1,3}(?:[.,]\d{3})*[.,]\d{2})\s+'
    r'(\d{1,3}(?:[.,]\d{3})*[.,]\d{2})(?:\s+IVA\s+\d[\d.,]*)?$',
    caseSensitive: false,
  );

  /// A row that opens with a full date: "16/11/26 HABITACION 2,150.00",
  /// "16-NOV-26 HABITACION 2,150.00".
  static final RegExp _datedRow = RegExp(
    r'^\s*(?:\d{1,2}(?:\s?([/.\-])\s?\d{1,2}\s?\1\s?|[\s/.\-]+'
    '$_months'
    r"\.?[\s/.\-'’]+)(?:\d{4}|\d{2})|"
    r'20\d{2}[/\-](?:0?[1-9]|1[0-2])[/\-](?:0?[1-9]|[12]\d|3[01]))\s+\S',
    caseSensitive: false,
  );

  /// "PRODUCTO: MAGNA 87 OCT", "CONCEPTO: ESTACIONAMIENTO"; a pump ticket
  /// may print no colon ("PRODUCTO MAGNA 87 OCT").
  static final RegExp _productLabel = RegExp(
    r'^(?:(?:producto|product|combustible|descripci[oó]n|concepto)\s*[:.]\s*|'
    r'(?:producto|combustible)\s+)(\S.*)$',
    caseSensitive: false,
  );

  /// The label of the amount paid for the product, most telling first:
  /// "IMPORTE:", "VALOR TOTAL:", then "TOTAL:". Not "VALOR UNITARIO:",
  /// "TOTAL GALONES:" or "SUBTOTAL:".
  static final List<RegExp> _amountLabels = [
    RegExp(
      r'^(?:(?:importe|monto|venta|valor)(?:\s+total)?|total\s+venta)'
      r'\s*:?\s*\$?\s*\d',
      caseSensitive: false,
    ),
    RegExp(
      r'^(?:gran\s+)?total(?:\s+a\s+pagar)?\s*:?\s*\$?\s*\d',
      caseSensitive: false,
    ),
  ];
  static final RegExp _quantityLabel = RegExp(
    r'^(?:total\s+)?(?:cantidad|cant|litros|volumen|galones)\.?\s*[:.]?\s*'
    r'(\d{1,4}(?:[.,]\d{1,3})?)\s*(lts?|l|litros?|gal(?:ones)?)?(?!\S)',
    caseSensitive: false,
  );

  static final RegExp _columnWord = RegExp(
    r'\b(?:litros|galones|precio|importe|cantidad|descripci[oó]n|total|'
    r'p\.?\s?u\.?)\b',
    caseSensitive: false,
  );

  /// What a card slip prints as its "CONCEPTO" or "DESCRIPCION": the kind
  /// of transaction ("VENTA", "VENTA PRESENCIAL", "COMPRA CON TARJETA").
  static final RegExp _transaction = RegExp(
    r'^(?:(?:ventas?|compra|consumo|pago|cargo|retiro|abono|transferencia|'
    r'dep[oó]sito|'
    r'purchase|sale|payment|presencial|normal|contado|efectivo|tarjeta|'
    r'cr[eé]dito|d[eé]bito|l[ií]nea|online|visa|master\s?card|amex|'
    r'american\s+express|carnet|electron|de|en|con|a)\s*)+$',
    caseSensitive: false,
  );

  /// A payment on a folio under names the totals words do not cover: "TC
  /// VISA", "DISCOVER", "PREPAGO AGENCIA", "DEPOSITO EN GARANTIA", "ADVANCE
  /// DEPOSIT", "TRANSFERENCIA BANCARIA", "CXC AGENCIA".
  ///
  /// These words also stand on charges ("DEPOSITO LLAVE 50.00", "SIM card",
  /// "COMISION POR TARJETA"), so a row with one of them is a payment only
  /// when it takes money off or comes to the charges of the folio.
  static final RegExp _folioPayment = RegExp(
    r'\b(?:pagos?|prepago|anticipo|dep[oó]sito|deposit|transferencia|agencia|'
    r'cxc|abono|payment|prepaid|efectivo|tarjeta|card)\b',
    caseSensitive: false,
  );

  /// A card by its brand: always a payment.
  static final RegExp _cardPayment = RegExp(
    r'\b(?:tc|visa|master\s?card|amex|american\s+express|discover|diners)\b',
    caseSensitive: false,
  );

  /// "10 PIEZAS BBQ", "12 PZAS": how many pieces a dish has.
  static final RegExp _pieces =
      RegExp(r'^\d{1,3}\s*(?:pzas?|pz|piezas?|pcs?)\b', caseSensitive: false);

  /// One thing sold, printed as fields: "PRODUCTO: MAGNA 87 OCT" /
  /// "CANTIDAD: 38.462 LTS" / "IMPORTE: $918.86". Only when the receipt
  /// names a single product and its amount follows within a few rows.
  static List<ReceiptItem> _labelled(
    List<String> texts,
    List<_Row> parsed,
    _Style style,
  ) {
    final products = <(int, String)>[];
    for (var i = 0; i < texts.length; i++) {
      final label = _productLabel.firstMatch(texts[i]);
      if (label == null || parsed[i].amount != null) continue;
      final name = _nameOf(label[1]!, style).$1;
      // A card voucher's "CONCEPTO: VENTA" names no product, nor does a
      // heading ("PRODUCTO LITROS PRECIO IMPORTE").
      if (!_looksLikeName(name) ||
          _transaction.hasMatch(name) ||
          _columnWord.hasMatch(name)) {
        continue;
      }
      products.add((i, name));
    }
    if (products.length != 1) return const [];
    final (at, name) = products.single;
    final until = at + 8 < texts.length ? at + 8 : texts.length - 1;
    String? quantity;
    for (var j = at + 1; j <= until; j++) {
      final measured = _quantityLabel.firstMatch(texts[j]);
      if (measured == null) continue;
      quantity = measured[2] == null
          ? _plain(measured[1]!)
          : '${_plain(measured[1]!)} ${measured[2]}';
      break;
    }
    for (final label in _amountLabels) {
      for (var j = at + 1; j <= until; j++) {
        if (!label.hasMatch(texts[j]) || parsed[j].amount == null) continue;
        return [
          ReceiptItem(
            description: name,
            quantity: quantity,
            amountText: parsed[j].amount,
            firstRow: at,
            lastRow: j,
          ),
        ];
      }
    }
    return const [];
  }

  /// The two columns read as two blocks: every name, then every price
  /// ("1 CAFE AMERICANO" / "1 PAN DULCE" / "45.00" / "25.00"). They are
  /// paired in order only when a run of names is followed at once by exactly
  /// as many lone prices; anything else is not guessed.
  static List<ReceiptItem> _pairedBlocks(
    List<String> texts,
    List<_Row> parsed,
    bool Function(int) summary,
    _Style style,
  ) {
    final n = texts.length;
    bool nameOnly(int i) =>
        _wordy.hasMatch(texts[i]) &&
        !_heading.hasMatch(texts[i]) &&
        !summary(i) &&
        parsed[i].tail.isEmpty &&
        _looksLikeName(_nameOf(parsed[i].head, style).$1);
    bool priceOnly(int i) =>
        parsed[i].figuresOnly &&
        parsed[i].tail.length == 1 &&
        parsed[i].amounts.length == 1;
    var start = 0;
    while (start < n) {
      if (!nameOnly(start)) {
        start++;
        continue;
      }
      var end = start;
      while (end + 1 < n && nameOnly(end + 1)) {
        end++;
      }
      var after = end + 1;
      while (after < n && priceOnly(after)) {
        after++;
      }
      final names = end - start + 1;
      if (names >= 2 && after - (end + 1) == names) {
        return [
          for (var k = 0; k < names; k++)
            ReceiptItem(
              description: _nameOf(parsed[start + k].head, style).$1,
              quantity: _nameOf(parsed[start + k].head, style).$2,
              amountText: parsed[end + 1 + k].amount,
              firstRow: start + k,
              lastRow: end + 1 + k,
            ),
        ];
      }
      start = end + 1;
    }
    return const [];
  }

  /// [extract], falling back to line-by-line parsing for crops with no prices.
  static List<ReceiptItem> parseSmart(List<String> rows) {
    final items = extract(rows);
    return items.isNotEmpty ? items : parseAll(rows);
  }

  static List<ReceiptItem> parseAll(List<String> rows) {
    final items = <ReceiptItem>[];
    for (final row in rows) {
      final item = parse(row);
      if (item != null) items.add(item);
    }
    return items;
  }

  static ReceiptItem? parse(String row) {
    var text = TextNormaliser.collapseSpaces(row);
    if (TextNormaliser.letterCount(text) < 2) return null;
    if (_summaryOf(text, _parse(text)).$1 == _Summary.yes) return null;

    String? amountText;
    final trailing = _trailingAmounts.firstMatch(text);
    if (trailing != null) {
      final amounts = _amount.allMatches(trailing.group(1)!).toList();
      if (amounts.isNotEmpty) amountText = amounts.last.group(0);
      text = text.substring(0, trailing.start).trim();
    }

    String? quantity;
    final qty = _leadingQuantity.firstMatch(text);
    if (qty != null) {
      quantity = qty.group(1);
      text = text.substring(qty.end).trim();
    }

    text = text
        .replaceAll(RegExp(r'^[\s\-*.·:]+|[\s\-*.·:$]+$'), '')
        .trim();
    if (TextNormaliser.letterCount(text) < 2) return null;

    return ReceiptItem(
      description: text,
      quantity: quantity,
      amountText: amountText,
    );
  }
}

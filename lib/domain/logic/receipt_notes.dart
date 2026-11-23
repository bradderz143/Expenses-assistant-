import 'text_normaliser.dart';

/// What a note is about; decides its icon. In the order the notes are shown:
/// what matters most for the claim first, conveniences last.
enum ReceiptNoteKind {
  preBill,
  invoice,
  tip,
  discount,
  exchangeRate,
  offer,
  wifi,
  toilet,
  parking,
  returns,
}

/// Something printed on a receipt that is worth knowing about: how to get a
/// tax invoice, whether the tip is included, an offer for next time, the
/// Wi-Fi password. Shown to the user only, never exported.
class ReceiptNote {
  const ReceiptNote(this.kind, this.title, {this.detail, this.printed});

  final ReceiptNoteKind kind;

  /// Plain English, e.g. "Tax invoice (factura): ask within 30 days".
  final String title;

  /// More in English: a web address, a password, how to do it.
  final String? detail;

  /// The wording on the receipt it came from.
  final String? printed;

  @override
  String toString() => 'ReceiptNote($kind, $title, $detail)';
}

/// What a row of running text is about, so that a sentence about one thing
/// ("CAMBIOS DENTRO DE 15 DIAS") is not read as part of another (the
/// invoice deadline).
enum _Topic { invoice, returns, promo, privacy, wifi, toilet, tip, parking }

/// The rows of a receipt three ways: as read, without accents, and with the
/// commonest misreadings put right (what the rules look at).
class _Rows {
  _Rows(List<String> rows) {
    for (final row in rows) {
      final read = TextNormaliser.collapseSpaces(row);
      if (read.isEmpty) continue;
      raw.add(read);
      final unaccented = TextNormaliser.stripDiacritics(read);
      plain.add(unaccented);
      text.add(ReceiptNotes._repair(unaccented));
    }
  }

  final List<String> raw = [];
  final List<String> plain = [];
  final List<String> text = [];

  int get length => raw.length;
}

/// An amount at the end of a row: as printed, in hundredths, and its sign.
typedef _Amount = ({String text, int minor, bool negative});

/// "30 days", "72 hours"; [later] when it is a wait ("24 HRS DESPUES DE TU
/// COMPRA") rather than a time limit.
typedef _Span = ({int n, String unit, bool later});

/// Finds [ReceiptNote]s in the text read from a receipt, by fixed rules, so
/// it works offline and says nothing it cannot back up.
class ReceiptNotes {
  ReceiptNotes._();

  /// A long list is not read: only the most important notes are shown.
  static const int _most = 5;

  static RegExp _re(String pattern) => RegExp(pattern, caseSensitive: false);

  /// The notes for a receipt read as [rows], at most one of each kind, the
  /// most important first.
  static List<ReceiptNote> find(List<String> rows) {
    final t = _Rows(rows);
    final topics = [for (var i = 0; i < t.length; i++) _topicOf(t, i)];
    final preBill = _preBillNote(t);
    final notes = <ReceiptNote?>[
      preBill,
      _invoiceNote(t, topics, preBill: preBill != null),
      _tipNote(t),
      _discountNote(t),
      _exchangeRateNote(t),
      _offerNote(t, topics),
      _wifiNote(t),
      _toiletNote(t),
      _parkingNote(t),
      _returnsNote(t, topics),
    ];
    return notes.whereType<ReceiptNote>().take(_most).toList();
  }

  // ---------------------------------------------------------------------
  // Reading the text
  // ---------------------------------------------------------------------

  static final RegExp _word = RegExp(r'[A-Za-z0-9]+');
  static final RegExp _digitsWithO = RegExp(r'^(?=.*\d)[\dO]{2,}$');
  static final RegExp _capitalsWithL = RegExp(r'^(?=(?:.*[A-Z]){2})[A-Zl]+$');
  static final RegExp _lettersWith01 = RegExp(r'^[A-Za-z]+(?:[01][A-Za-z]+)+$');
  static final RegExp _digitInside = RegExp(r'(?<=[A-Za-z])[01](?=[A-Za-z])');
  static final RegExp _zeroAtEdge = RegExp(r'^(?:0[A-Za-z]{3,}|[A-Za-z]{3,}0)$');

  /// The words as the till printed them, where that is certain:
  /// "FACTURAClON" is "FACTURACION" (a small L among capitals is a capital
  /// I), "F0LIO" and "FOLI0" are "FOLIO", "N0 INCLUIDA" is "NO INCLUIDA",
  /// and "3O DIAS" is "30 DIAS". "USD0.90" keeps its zero: it is an amount.
  static String _repair(String row) => row.replaceAllMapped(_word, (m) {
        var w = m[0]!;
        if (w == 'N0') return 'NO';
        if (_digitsWithO.hasMatch(w)) return w.replaceAll('O', '0');
        if (_zeroAtEdge.hasMatch(w)) {
          final beside = w.startsWith('0')
              ? (m.start > 0 ? row[m.start - 1] : '')
              : (m.end < row.length ? row[m.end] : '');
          return beside == '.' || beside == ',' ? w : w.replaceAll('0', 'O');
        }
        if (w.contains('l') && _capitalsWithL.hasMatch(w)) {
          w = w.replaceAll('l', 'I');
        }
        if (w.length >= 4 && _lettersWith01.hasMatch(w)) {
          w = w.replaceAllMapped(
              _digitInside, (d) => d[0] == '0' ? 'O' : 'I');
        }
        return w;
      });

  static final RegExp _price = RegExp(r'\d[.,]\d{2}\b');

  /// Running text: long enough to be words, and not a line of amounts.
  static bool _prose(String l) => !_price.hasMatch(l) && l.length >= 6;

  static final RegExp _returnsWord = _re(
    r'devoluci|\bcambios\b|reembols|\brefunds?\b|\breturns\b|\bexchanges\b|'
    r'garantia|warranty|all\s+sales',
  );
  static final RegExp _promoWord = _re(
    r'encuesta|survey|opinion|feedback|cuentanos|experiencia|tell\s+us|'
    r'descuento|discount|\bgratis\b|\bfree\b|\bcupon|coupon|promoci|sorteo|'
    r'\bpuntos\b|vigencia|valido\s+(hasta|por)',
  );
  static final RegExp _privacy = _re(
    r'privacidad|privacy|aviso\s+legal|terminos\s+y\s+condiciones|'
    r'terms\s+(and|&)\s+conditions',
  );
  static final RegExp _wifiWord =
      _re(r'wi-?\s?fi\b|\bssid\b|contrasena|password');
  static final RegExp _tipWord = _re(r'propina|\btips?\b|gratuity');

  static _Topic? _topicOf(_Rows t, int i) {
    final l = t.text[i];
    if (_asksForInvoice(t, i)) return _Topic.invoice;
    if (_returnsWord.hasMatch(l)) return _Topic.returns;
    if (_promoWord.hasMatch(l)) return _Topic.promo;
    if (_privacy.hasMatch(l)) return _Topic.privacy;
    if (_wifiWord.hasMatch(l)) return _Topic.wifi;
    if (_toilet.hasMatch(l)) return _Topic.toilet;
    if (_tipWord.hasMatch(l)) return _Topic.tip;
    if (_parkingWord.hasMatch(l)) return _Topic.parking;
    return null;
  }

  static final RegExp _runsOn = _re(
    r'(\b(de|del|al|a|en|y|o|e|u|ni|que|con|sin|por|para|los|las|el|la|un|'
    r'una|su|tu|sus|tus|este|esta|dentro|hasta|the|of|to|for|in|on|at|by|'
    r'and|or|with|your|our|an)|[,:])$',
  );
  static final RegExp _carriesOn = _re(
    r'^(de|del|al|en|y|o|e|ni|que|con|sin|por|para|dentro|hasta|antes|'
    r'despues|durante|and|or|with|within|for|of|to|on|at|by|from)\b',
  );
  static final RegExp _startsSmall = RegExp(r'^[a-z]');

  /// Whether the row under [upper] carries its sentence on: "OBTEN 10% DE" /
  /// "DESCUENTO", "Returns accepted within 90 days" / "with original
  /// receipt". "HABITACION 204" / "TARIFA NO REEMBOLSABLE" are two things.
  static bool _linked(_Rows t, int upper) {
    final next = t.text[upper + 1];
    return _runsOn.hasMatch(t.text[upper]) ||
        (!_hasAddress(t.plain[upper + 1]) &&
            (_startsSmall.hasMatch(next) || _carriesOn.hasMatch(next)));
  }

  /// The row at [i] and the running text round it about the same [topic]
  /// (a sentence the printer wrapped over several lines). Rows that lead
  /// back to another subject belong to that one.
  static List<int> _paragraph(
    _Rows t,
    List<_Topic?> topics,
    int i,
    _Topic topic, {
    int reach = 3,
  }) {
    bool same(int j) => topics[j] == null || topics[j] == topic;
    // [far] joins the paragraph across the break under [upper].
    bool joins(int far, int upper) =>
        topics[far] == topic || _linked(t, upper) || _hasAddress(t.plain[far]);
    var start = i;
    var j = i - 1;
    for (; j >= 0 && i - j <= reach; j--) {
      if (!_prose(t.text[j]) ||
          t.text[j].endsWith('.') ||
          !same(j) ||
          !joins(j, j)) {
        break;
      }
      start = j;
    }
    if (j >= 0 && i - j <= reach && !same(j)) {
      while (start < i && topics[start] != topic) {
        start++;
      }
    }
    var end = i;
    while (end + 1 < t.length &&
        end - i < reach &&
        _prose(t.text[end + 1]) &&
        !t.text[end].endsWith('.') &&
        same(end + 1) &&
        joins(end + 1, end)) {
      end++;
    }
    return [for (var k = start; k <= end; k++) k];
  }

  static String _join(List<String> rows, Iterable<int> indexes) =>
      indexes.map((i) => rows[i]).join(' ');

  static final RegExp _amount = RegExp(
    r'(-\s?)?(?:[A-Za-z]{0,3}\.?\s?[$£€]|Bs\.?\s?S?\.?|[A-Z]{3}|Q)?\s?(-)?'
    r'((?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}|\d{1,3}(?:[.,]\d{3})+)'
    r'(-)?(?:\s?(?:[A-Z]{3}|M\.?N\.?))?\s*$',
  );

  /// The amount a row ends with: "\$18.65", "-41.50", "Bs 52,20",
  /// "50.00 MXN", and "8.500" where money has no decimals.
  static _Amount? _amountAt(String l) {
    final m = _amount.firstMatch(l);
    if (m == null) return null;
    final number = m[3]!;
    final cents = RegExp(r'[.,](\d{2})$').firstMatch(number);
    final whole = (cents == null ? number : number.substring(0, cents.start))
        .replaceAll(RegExp(r'[.,]'), '');
    final units = int.tryParse(whole);
    if (units == null) return null;
    return (
      text: number,
      minor: units * 100 + (cents == null ? 0 : int.parse(cents[1]!)),
      negative: m[1] != null || m[2] != null || m[4] != null,
    );
  }

  static final RegExp _count = _re(
    r'(?<![\d.,/-])(\d{1,3})\s*(dias?|days?|horas?|hrs?|hours?)\b',
  );
  static final RegExp _waitBefore = _re(
    r'(despues\s+de|pasad[ao]s|transcurrid[ao]s|a\s+partir\s+de|after)\s+'
    r'(l[ao]s\s+)?$',
  );
  static final RegExp _waitAfter = _re(
    r'^\s*(habiles\s+|naturales\s+)?(despues|posterior(es)?|after|later)',
  );
  static final RegExp _becomes = _re(r'disponible|available|podra');

  /// "SU FACTURA SE ENVIARA DENTRO DE LAS 24 HRS": when it comes, not a
  /// limit on asking.
  static final RegExp _comes = _re(
    r'\b(generara|enviara|recibira|llegara|estara|will\s+be\s+sent)\b'
    r'[^.]{0,40}$',
  );
  static final RegExp _ofTheMonth = _re(
    r'^\s*(habiles\s+|naturales\s+)?del\s+(mes|siguiente|proximo)',
  );
  static final RegExp _limitBefore = _re(
    r'(tiene[sn]?|cuenta[sn]?\s+con|dentro\s+de(\s+l[ao]s)?|plazo(\s+de)?|'
    r'maximo(\s+de)?|within|you\s+have|primer[ao]s|siguientes|'
    r'durante(\s+l[ao]s)?)\s*$',
  );
  static final RegExp _limitAfter = _re(
    r'^\s*(habiles\s+|naturales\s+)?(para\s+(solicit|factur|gener|realiz|'
    r'obten|cambi|devol)|posteriores|siguientes|a\s+partir|'
    r'despues\s+de\s+(su|tu|la)\s+compra|'
    r'(after|of|from)\s+(the\s+)?(date\s+of\s+)?purchase)',
  );

  /// The lengths of time in running text: "CUENTA CON 30 DIAS", "DENTRO DE
  /// LAS 48 HORAS". Hours count only when worded as a limit or a wait:
  /// "HASTA LAS 19 HRS" is a time of day and "ABIERTO 24 HRS" opening hours.
  static List<_Span> _spans(String text) {
    final spans = <_Span>[];
    for (final m in _count.allMatches(text)) {
      final n = int.parse(m[1]!);
      if (n == 0) continue;
      final hours = m[2]!.toLowerCase().startsWith('h');
      final before = text.substring(0, m.start);
      final rest = text.substring(m.end);
      final later = _waitBefore.hasMatch(before) ||
          (_waitAfter.hasMatch(rest) && _becomes.hasMatch(text));
      if (!later && _comes.hasMatch(before)) continue;
      if (!later) {
        // "LOS PRIMEROS 5 DIAS DEL MES SIGUIENTE" is a date, not a length.
        if (_ofTheMonth.hasMatch(rest)) continue;
        if (hours &&
            !_limitBefore.hasMatch(before) &&
            !_limitAfter.hasMatch(rest)) {
          continue;
        }
      }
      final unit = hours ? 'hour' : 'day';
      spans.add((n: n, unit: n == 1 ? unit : '${unit}s', later: later));
    }
    return spans;
  }

  // ---------------------------------------------------------------------
  // Web and e-mail addresses
  // ---------------------------------------------------------------------

  static const String _tlds =
      'com|mx|net|org|cloud|app|co|ve|sv|es|br|gt|uk|io|info|gob|gov';

  static final RegExp _web = _re(
    r'(https?://\S+|www\.\S+|\b[a-z0-9-]{3,}(\.[a-z0-9-]+)*\.(' +
        _tlds +
        r')\b(\.[a-z]{2}\b)?(/\S*)?)',
  );

  static final RegExp _email =
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+');

  /// A web address that is about something else: the privacy notice.
  static final RegExp _otherSite = _re(r'privacidad|privacy|aviso\s+legal');

  /// The tax authority's site on a printed invoice, or the card terminal's
  /// maker on the slip: never where the shop issues its invoices.
  static final RegExp _notTheShop = _re(
    r'\.go[bv]\b|\b(clip|getnet|mercadopago|sumup|squareup|zettle|izettle|'
    r'billpocket|netpay|paypal|stripe|visa|mastercard|americanexpress|prosa|'
    r'banorte|bbva|santander|banamex|citibanamex|hsbc|scotiabank)\.',
  );

  /// "www.example. com. mx/": OCR puts spaces round the dots of an address.
  static String _joinAddress(String line) => line
      .replaceAllMapped(
        _re(r'\s*\.\s*(?=(' + _tlds + r')\b)'),
        (_) => '.',
      )
      .replaceAllMapped(_re(r'(www)\s*\.\s*(?=\w)'), (m) => '${m[1]}.')
      .replaceAllMapped(_re(r'(https?)\s*:\s*/\s*/\s*'), (m) => '${m[1]}://');

  /// The first address of a shop's own page in [rows].
  static String? _webIn(Iterable<String> rows) {
    for (final row in rows) {
      final line = _joinAddress(row).replaceAll(_email, ' ');
      if (_otherSite.hasMatch(line)) continue;
      for (final m in _web.allMatches(line)) {
        final site = m[0]!.replaceAll(RegExp(r'[.,;:)]+$'), '');
        if (!_notTheShop.hasMatch(site)) return site;
      }
    }
    return null;
  }

  static bool _hasAddress(String row) {
    final line = _joinAddress(row);
    return _email.hasMatch(line) || _web.hasMatch(line);
  }

  // ---------------------------------------------------------------------
  // Not the final receipt
  // ---------------------------------------------------------------------

  /// "*** PRECUENTA ***", "PRE-CUENTA", "SALDO DE MESA", "THIS IS NOT A
  /// RECEIPT": the bill brought to the table before paying.
  static final RegExp _preBill = _re(
    r'\bpre\s?-?\s?[cq]uenta\b|\bpre\s?-?\s?(check|bill|factura|ticket|'
    r'cierre)\b|saldo\s+de\s+mesa|'
    r'\bno\s+es\s+(un\s+)?(comprobante|recibo)\s+de\s+pago|'
    r'\bnot\s+a\s+receipt\b',
  );

  /// "** COMANDA **" as the heading of the slip; "MESA 5 COMANDA: 1023" on
  /// a paid ticket is only its order number.
  static final RegExp _orderSlip =
      _re(r'^\W*(comanda|orden\s+de\s+cocina|cuenta\s+parcial)\W*$');

  /// "FACTURA PROFORMA", "COTIZACION No. 123": a price given in advance.
  static final RegExp _quote = _re(
    r'\bpro\s?-?\s?forma\b|'
    r'^\W*(cotizacion|presupuesto|quotation|estimate|quote)\b\W*'
    r'(no|num|numero)?[\W\d]*$',
  );

  static ReceiptNote? _preBillNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      final quote = _quote.hasMatch(l);
      if (!quote && !_preBill.hasMatch(l) && !_orderSlip.hasMatch(l)) continue;
      return ReceiptNote(
        ReceiptNoteKind.preBill,
        quote
            ? 'Quote or pro-forma, not a receipt'
            : 'Pre-bill, not the final receipt',
        detail: 'Ask for the receipt or tax invoice once it is paid.',
        printed: t.raw[i],
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Tax invoice
  // ---------------------------------------------------------------------

  /// "factura", "facturar", "facturacion", "autofactura", also read as
  /// "factua" and "Factuar"; a CFDI or an invoice only when it is being
  /// offered.
  static final RegExp _invoiceWord = _re(
    r'\b(auto)?factu[ra]|'
    r'\b(solicit|obten|gener|descarg|requier)\w*\s+(tu\s+|su\s+|el\s+|un\s+)?'
    r'cfdi\b|'
    r'\b(request|need|require|obtain|get)\s+(an?\s+|your\s+|a\s+full\s+)?'
    r'(vat\s+|tax\s+)?invoice\b|'
    r'\b(vat|tax)\s+invoice\s+(is\s+)?(available|on\s+request)',
  );

  /// "factura" that is not about getting one: "ESTE TICKET NO ES FACTURA",
  /// the slogan "EXIJA SU FACTURA", "No. de factura", "TICKET FACTURADO",
  /// "Autorizacion numeracion de facturacion 18764...", "CAMBIOS CON TICKET
  /// O FACTURA" (what to bring), a survey asking for its number.
  static final RegExp _notAboutInvoicing = _re(
    r'\bno\s+(es|constituye|representa)\s+(una?\s+)?factura|'
    r'no\s+(es\s+)?valid[oa]\s+como\s+factura|no\s+sustituye|\bexij[ae]|'
    r'factura\s+global|facturad[oa]s?\b|factura(r|do)?\s+a\s*:|'
    r'(numeracion|resolucion|autorizacion|rango|prefijo)\s+(de\s+)?factura|'
    r'\bdian\b|'
    r'(numero|n[°ºo]\.|num\.?|nro\.?|#)\s*(de\s+)?(tu\s+|su\s+|la\s+)?'
    r'factura\b|\bno\s+de\s+factura\b|'
    r'\b(ticket|nota|comprobante|recibo)\s+[ouy]\s+factura\b|'
    r'\b(con|presenta\w*|mostrando)\s+(su\s+|la\s+|el\s+|tu\s+)?factura\b|'
    r'encuesta|survey',
  );

  /// "FACTURA", "FACTURA: A 1234", "FACTURA SERIE A No. 4521", "FACTURA DE
  /// VENTA POS No. 12345", "FACTURA CONSUMIDOR FINAL", "FACTURA PROFORMA":
  /// a row that opens with the noun names the document or gives its number.
  /// "FACTURA TU TICKET EN:" and "Factura en linea" tell how to get one.
  static final RegExp _invoiceHeading = _re(
    r'^\W*(copia\s+(de\s+)?|original\s+)?factura\b'
    r'(?!\s+(tu|su|aqui|en|ya|ahora|desde)\b)',
  );

  static final RegExp _leadsToAddress =
      _re(r'electronica|linea|online|internet|web|:\s*$');

  /// Whether the row at [i] tells how to get a tax invoice. A heading does
  /// only with an address: on the row, or under "Factura electronica:". A
  /// shop's own site under the title "FACTURA" is just its letterhead.
  static bool _asksForInvoice(_Rows t, int i) {
    final l = t.text[i];
    if (!_invoiceWord.hasMatch(l) || _notAboutInvoicing.hasMatch(l)) {
      return false;
    }
    if (_invoiceHeading.hasMatch(l)) {
      return _hasAddress(t.plain[i]) ||
          (_leadsToAddress.hasMatch(l) &&
              i + 1 < t.length &&
              _hasAddress(t.plain[i + 1]));
    }
    return true;
  }

  /// "ESTE TICKET NO ES UN COMPROBANTE FISCAL", "DOCUMENTO SIN VALOR
  /// FISCAL", "NO VALIDO COMO FACTURA".
  static final RegExp _notTaxInvoice = _re(
    r'\bno\s+es\s+(una?\s+)?(factura|comprobante\s+fiscal)|'
    r'no\s+(es\s+)?valid[oa]\s+como\s+(factura|comprobante\s+fiscal)|'
    r'sin\s+(valor|validez)\s+fiscal|'
    r'no\s+(tiene|posee)\s+(valor|validez)\s+fiscal|'
    r'no\s+sustituye\s+(a\s+)?(la\s+|el\s+|al\s+)?(factura|ticket\s+fiscal|'
    r'comprobante\s+fiscal)|\bno\s+fiscal\b|'
    r'not\s+a\s+(vat|tax)\s+(invoice|receipt)',
  );

  /// What only an electronic tax invoice prints: Mexico's "FOLIO FISCAL"
  /// and "SELLO DIGITAL", Guatemala's and El Salvador's "DOCUMENTO
  /// TRIBUTARIO ELECTRONICO", Colombia's "CUFE".
  static final RegExp _eInvoice = _re(
    r'folio\s+fiscal|sello\s+digital|cadena\s+original|'
    r'representacion\s+impresa|uso\s+(de\s+|del\s+)?cfdi|'
    r'documento\s+tributario\s+electronico|codigo\s+de\s+generacion|'
    r'sello\s+de\s+recepcion|\bcufe\b|\bcude\b|'
    r'factura\s+electronica\s+de\s+venta',
  );
  static final RegExp _authorisation = _re(r'autorizacion');
  static final RegExp _uuid = _re(
    r'\b[0-9a-f]{8}\s?-\s?[0-9a-f]{4}\s?-\s?[0-9a-f]{4}\s?-\s?[0-9a-f]{4}'
    r'\s?-\s?[0-9a-f]{12}\b',
  );
  static final RegExp _fiscalPrinter = _re(r'\bseniat\b');

  /// "NIT: CF", "CLIENTE: CONSUMIDOR FINAL", "PUBLICO EN GENERAL" and the
  /// tax IDs that stand for nobody in particular.
  static final RegExp _finalConsumer = _re(
    r'consumidor\s+final|publico\s+en\s+general|\bX[AE]XX010101000\b|'
    r'\b(nit|cliente|nombre)\s*:?\s*c\s?[/.]?\s?f\b\.?\s*$|\b2{10,12}\b',
  );

  /// The row where the receipt shows itself to be a tax invoice already, or
  /// -1.
  static int _invoiceProof(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      if (_eInvoice.hasMatch(t.text[i])) return i;
      if (_authorisation.hasMatch(t.text[i]) &&
          (_uuid.hasMatch(t.plain[i]) ||
              (i + 1 < t.length && _uuid.hasMatch(t.plain[i + 1])))) {
        return i;
      }
    }
    // A Venezuelan fiscal printer: the authority's name over a "FACTURA".
    if (t.text.any(_fiscalPrinter.hasMatch)) {
      return t.text.indexWhere(_invoiceHeading.hasMatch);
    }
    return -1;
  }

  static ReceiptNote? _alreadyInvoice(_Rows t) {
    final proof = _invoiceProof(t);
    if (proof < 0) return null;
    final nobody = t.text.indexWhere(_finalConsumer.hasMatch);
    if (nobody >= 0) {
      return ReceiptNote(
        ReceiptNoteKind.invoice,
        'Tax invoice without a company tax ID',
        detail: 'Made out to a final consumer, not to a company.\n'
            'If your company needs its tax ID on the invoice, ask the shop '
            'to issue it again.',
        printed: t.raw[nobody],
      );
    }
    return ReceiptNote(
      ReceiptNoteKind.invoice,
      'This is already a tax invoice',
      detail: 'Nothing more to request. Check that it is made out to your '
          'company.',
      printed: t.raw[proof],
    );
  }

  /// The rows where [pattern] is found, on one row or wrapped over two
  /// ("ESTE TICKET NO ES UN" / "COMPROBANTE FISCAL"); empty when it is not.
  static List<int> _rowsWith(_Rows t, RegExp pattern) {
    final whole = t.text.indexWhere(pattern.hasMatch);
    if (whole >= 0) return [whole];
    for (var i = 0; i + 1 < t.length; i++) {
      if (pattern.hasMatch('${t.text[i]} ${t.text[i + 1]}')) return [i, i + 1];
    }
    return const [];
  }

  static ReceiptNote? _invoiceNote(
    _Rows t,
    List<_Topic?> topics, {
    required bool preBill,
  }) {
    final disclaimer = _rowsWith(t, _notTaxInvoice);
    // A document that says it is not one is never called a tax invoice.
    if (!preBill && disclaimer.isEmpty) {
      final already = _alreadyInvoice(t);
      if (already != null) return already;
    }
    final cues = [
      for (var i = 0; i < t.length; i++)
        if (topics[i] == _Topic.invoice) i,
    ];
    if (cues.isNotEmpty) return _howToInvoice(t, topics, cues);
    if (disclaimer.isEmpty || preBill) return null;
    return ReceiptNote(
      ReceiptNoteKind.invoice,
      'This ticket is not a tax invoice',
      detail: 'Ask the shop for a tax invoice (factura) if your company '
          'needs one.',
      printed: _join(t.raw, disclaimer),
    );
  }

  /// How far the wording about invoices runs on after a row about them.
  static const int _invoiceReach = 6;

  static final RegExp _atPurchase =
      _re(r'(al|en\s+el)\s+momento|at\s+the\s+time\s+of');
  static final RegExp _onTheDay = _re(
    r'(unicamente|solo|solamente)\s+(el\s+)?(mismo\s+)?dia\s+de\s+'
    r'(la|su|tu)\s+(compra|consumo|visita)|\bel\s+mismo\s+dia\b|'
    r'\bsame\s+day\b',
  );
  static final RegExp _sameMonth = _re(
    r'(mismo|dentro\s+del?|ultimo\s+dia\s+del?|fin(al)?\s+del?)\s+mes|'
    r'mes\s+(en\s+curso|corriente|actual)|'
    r'mes\s+de\s+(la\s+|su\s+|tu\s+)?(compra|consumo|emision)|'
    r'same\s+month|end\s+of\s+the\s+month',
  );

  /// The rows just above the first one about invoices that lead into it
  /// ("CUENTA CON 30 DIAS" over "PARA FACTURAR"), unless they run on from
  /// another subject.
  static List<int> _leadIn(_Rows t, List<_Topic?> topics, int first) {
    final rows = <int>[];
    for (var j = first - 1; j >= 0 && first - j <= 4; j--) {
      if (topics[j] != null) return const [];
      if (!_prose(t.text[j]) || t.text[j].endsWith('.')) break;
      if (!_linked(t, j) && !_count.hasMatch(t.text[j])) break;
      if (first - j <= 2) rows.insert(0, j);
    }
    return rows;
  }

  static ReceiptNote _howToInvoice(
    _Rows t,
    List<_Topic?> topics,
    List<int> cues,
  ) {
    // Invoice wording is often spread over a few short paragraphs; it ends
    // where another subject or the amounts begin.
    final found = <int>{};
    for (final c in cues) {
      found.add(c);
      for (var j = c + 1; j < t.length && j <= c + _invoiceReach; j++) {
        final topic = topics[j];
        if (topic != null && topic != _Topic.invoice) break;
        if (topic == null && _price.hasMatch(t.text[j])) break;
        found.add(j);
      }
    }
    final rows = found.toList()..sort();
    final all = [..._leadIn(t, topics, cues.first), ...rows];
    // Joined: "solicitela en el" / "momento de la compra" wraps.
    final text = _join(t.text, rows);
    final wider = _join(t.text, all);

    _Span? spanIn(String s, {required bool later}) {
      for (final span in _spans(s)) {
        if (span.later == later) return span;
      }
      return null;
    }

    final limit = spanIn(text, later: false) ?? spanIn(wider, later: false);
    final wait = spanIn(text, later: true);
    final atPurchase = _atPurchase.hasMatch(wider);
    final when = limit != null
        ? 'request it within ${limit.n} ${limit.unit}'
        : _sameMonth.hasMatch(wider)
            ? 'request it within the same month'
            : _onTheDay.hasMatch(wider)
                ? 'request it on the day of purchase'
                : atPurchase
                    ? 'ask for it when paying'
                    : null;
    final web = _webIn(rows.map((i) => t.plain[i])) ??
        _webIn(all.map((i) => t.plain[i]));
    final folio = _folioIn(t, all, from: cues.first);
    String? email;
    for (final i in all) {
      final m = _email.firstMatch(_joinAddress(t.plain[i]));
      if (m != null) {
        email = m[0];
        break;
      }
    }
    final steps = [
      if (atPurchase && limit != null) 'Ask at the till when paying, or',
      if (web != null) 'Online: $web',
      if (folio != null) 'Invoice reference (folio): $folio',
      if (email != null) 'Invoice help: $email',
      if (wait != null)
        'Available ${wait.n} ${wait.unit} after the purchase',
    ];
    return ReceiptNote(
      ReceiptNoteKind.invoice,
      'Tax invoice (factura)${when == null ? ' available' : ': $when'}',
      detail: [
        ...steps,
        'Your company may need it for the claim.',
      ].join('\n'),
      printed: all
          .where((i) =>
              topics[i] == _Topic.invoice ||
              _count.hasMatch(t.text[i]) ||
              _atPurchase.hasMatch(t.text[i]))
          .map((i) => t.raw[i])
          .join(' '),
    );
  }

  /// "Folio para facturar: 0543104092632357", "Referencia de facturacion:"
  /// with the number on the next line: the reference the invoice site asks
  /// for.
  static final RegExp _folioLabel = _re(
    r'(?:folio|ticket|referencia|ref\.?|clave|codigo|id|numero|no\.?)\s+'
    r'(?:de\s+|para\s+)?factur(?:acion|ar|a)\b\s*[:=]?\s*(.*)$',
  );

  /// "FOLIO: 123456789012", "Ticket : 200000001", "CON SU NO. DE
  /// REFERENCIA" under the invoice wording: the same, less fully labelled.
  static final RegExp _plainLabel = _re(
    r'^\W*(?:con\s+)?(?:su\s+|tu\s+)?(?:(?:no\.?|num\.?|numero)\s+'
    r'(?:de\s+)?)?(folio|ticket|referencia|ref)\b\.?\s*'
    r'(?:no\.?|num\.?|numero|#)?\s*[:=#]?\s*(.*)$',
  );
  static final RegExp _folioValue = RegExp(r'^[A-Za-z0-9][A-Za-z0-9\- ]{3,40}$');

  /// A reference is mostly digits; words after the label are not one. A
  /// code of capitals and digits ("K7HM3PXQ9") counts after a full label.
  static String? _folioFrom(String text, {required bool labelled}) {
    final value = text.trim();
    if (!_folioValue.hasMatch(value)) return null;
    final compact = value.replaceAll(' ', '');
    final digits = RegExp(r'\d').allMatches(compact).length;
    if (digits >= 4 && digits * 2 >= compact.length) return compact;
    if (labelled &&
        !value.contains(' ') &&
        compact.length >= 6 &&
        digits >= 2 &&
        compact == compact.toUpperCase()) {
      return compact;
    }
    return null;
  }

  static String? _folioIn(_Rows t, List<int> rows, {required int from}) {
    String? next(int i) => rows.contains(i + 1)
        ? _folioFrom(t.text[i + 1], labelled: false)
        : null;
    for (final i in rows) {
      final m = _folioLabel.firstMatch(t.text[i]);
      if (m == null) continue;
      final value = m[1]!.trim().isEmpty
          ? next(i)
          : _folioFrom(m[1]!, labelled: true);
      if (value != null) return value;
    }
    for (final i in rows.where((i) => i >= from)) {
      final m = _plainLabel.firstMatch(t.text[i]);
      if (m == null) continue;
      final ticket = m[1]!.toLowerCase() == 'ticket';
      final value = m[2]!.trim().isEmpty
          ? (ticket ? null : next(i))
          : _folioFrom(m[2]!, labelled: false);
      if (value != null) return value;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Tip
  // ---------------------------------------------------------------------

  static final RegExp _tipNotIncluded = _re(
    r'(propinas?|servicio)\s+no\s+(esta\s+|va\s+)?incluid|'
    r'no\s+(se\s+)?incluyen?\s+(la\s+|el\s+)?'
    r'(propina|servicio(?!\s+(a|de)\b))|'
    r'(tips?|gratuity|service(\s+charge)?)\s+(is\s+|are\s+)?not\s+included|'
    r'not\s+includ(e|ing)\s+(tips?|gratuity|service)|\bsin\s+propina\b',
  );
  static final RegExp _tipIncluded = _re(
    r'(propina|servicio)\s+(\d{1,2}([.,]\d)?\s?%\s+)?(ya\s+)?(esta\s+)?'
    r'incluid|'
    r'incluyen?\s+(la\s+|el\s+|un\s+)?(\d{1,2}([.,]\d)?\s?%\s+(de\s+)?)?'
    r'(propina|servicio(?!\s+(a|de)\b))|'
    r'(tip|gratuity|service(\s+charge)?)\s+(is\s+)?(already\s+)?included|'
    r'(gratuity|service\s+charge|\btip)\b([^.]|\.\d){0,40}?\b(has|have)\s+'
    r'been\s+'
    r'(added|included)|'
    r'includes\s+(an?\s+)?(\d{1,2}(\.\d)?\s?%\s+)?(tip|gratuity|service)',
  );
  static final RegExp _tipVoluntary = _re(
    r'propina\s+(es\s+)?(voluntaria|opcional|no\s+(es\s+)?obligatoria)|'
    r'(tip|gratuity)\s+is\s+(optional|voluntary|not\s+(required|mandatory))',
  );

  static ReceiptNote? _tipNote(_Rows t) {
    final paid = _tipPaid(t);
    if (paid != null) return paid;
    final notIncluded = _rowsWith(t, _tipNotIncluded);
    if (notIncluded.isNotEmpty) {
      return ReceiptNote(
        ReceiptNoteKind.tip,
        'Tip not included in the total',
        printed: _join(t.raw, notIncluded),
      );
    }
    final included = _rowsWith(t, _tipIncluded);
    if (included.isNotEmpty) {
      return ReceiptNote(
        ReceiptNoteKind.tip,
        'Tip or service already included',
        detail: 'No need to tip again.',
        printed: _join(t.raw, included),
      );
    }
    final voluntary = t.text.indexWhere(_tipVoluntary.hasMatch);
    if (voluntary >= 0) {
      return ReceiptNote(
        ReceiptNoteKind.tip,
        'Tip is voluntary',
        printed: t.raw[voluntary],
      );
    }
    return null;
  }

  /// "Propina Tarjeta \$18.65", "10% SERVICIO Bs 52,20": a tip or service
  /// charge with its amount.
  static final RegExp _tipLine = _re(
    r'^\W*(?:\d{1,2}(?:[.,]\d)?\s?%\s+(?:de\s+)?)?'
    r'(propina|tips?|gratuity|gratificacion|service\s+charge|'
    r'cargo\s+(?:por|de|x)\s+servicio|servicio)\b',
  );
  static final RegExp _tipHint = _re(r'sugerid|suggest|recomend|guide|guia');
  static final RegExp _otherService = _re(r'servicio\s+(a|al|de|por|para)\b');
  static final RegExp _percent = RegExp(r'(\d{1,2}(?:[.,]\d)?)\s?%');
  static final RegExp _totalRow = _re(
    r'^\W*(gran\s+|importe\s+|monto\s+)?total\b'
    r'(?!\s+(de\s+)?(descuento|ahorro|saving|articulo|item|iva|impuesto))',
  );
  static final RegExp _subtotalRow = _re(r'^\W*sub\s?-?\s?t');

  /// A tip that was added, with its amount. A blank or zero tip line and a
  /// table of suggested tips say nothing; a line with a percentage ("Propina
  /// 10% 45.00") counts only when the amounts show it went into the total.
  static ReceiptNote? _tipPaid(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      final m = _tipLine.firstMatch(l);
      if (m == null || _tipHint.hasMatch(l)) continue;
      final amount = _amountAt(l);
      if (amount == null || amount.negative || amount.minor == 0) continue;
      final percent = _percent.firstMatch(l)?[1];
      final word = m[1]!.toLowerCase();
      // "SERVICIO 150.00" is something sold and "CARGO POR SERVICIO" may
      // be a booking fee; with a percentage that adds up it is the charge.
      final service = word.endsWith('servicio');
      if (service &&
          (percent == null || (word == 'servicio' && _otherService.hasMatch(l)))) {
        continue;
      }
      if (percent != null && !_wentIntoTotal(t, i, amount.minor)) continue;
      return ReceiptNote(
        ReceiptNoteKind.tip,
        '${service || word.startsWith('serv') ? 'Service charge' : 'Tip'} on this '
            'receipt: ${amount.text}${percent == null ? '' : ' ($percent%)'}',
        detail: 'Check whether your company wants tips claimed separately.',
        printed: t.raw[i],
      );
    }
    return null;
  }

  /// Whether the [tip] on row [i] plus one or two amounts of the same block
  /// (subtotal, tax) make the total printed under it.
  static bool _wentIntoTotal(_Rows t, int i, int tip) {
    for (var j = i + 1; j < t.length; j++) {
      if (!_totalRow.hasMatch(t.text[j])) continue;
      final total = _amountAt(t.text[j]);
      if (total == null) continue;
      final rest = total.minor - tip;
      if (rest <= 0) return false;
      var from = i;
      while (from > 0 && i - from < 4 && !_subtotalRow.hasMatch(t.text[from])) {
        from--;
      }
      final others = [
        for (var k = from; k < j; k++)
          if (k != i) _amountAt(t.text[k])?.minor,
      ].whereType<int>().toList();
      for (var a = 0; a < others.length; a++) {
        if (others[a] == rest) return true;
        for (var b = a + 1; b < others.length; b++) {
          if (others[a] + others[b] == rest) return true;
        }
      }
      return false;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Discount taken off this bill
  // ---------------------------------------------------------------------

  /// "1 Desc. 10% AICM -41.50", "TOTAL DESCUENTOS -45.00", "CUPON -30.00":
  /// a discount already taken off this bill.
  static final RegExp _discountLine = _re(
    r'^\W*(?:\d{1,2}\s+)?(?:\d{1,2}(?:[.,]\d)?\s?%\s+)?(?:total\s+(?:de\s+)?)?'
    r'(desc\.?|descuentos?|dscto\.?|dto\.?|discounts?|promocion|promo|'
    r'cortesia|cupon|coupon)\b',
  );
  static final RegExp _discountWordAtStart = _re(r'^(desc|dscto|dto|discount)');
  static final RegExp _condition = _re(r'mayor(es)?\s+a\b|\bminim');

  /// "USTED AHORRO 23.50", "TOTAL SAVINGS 23.50".
  static final RegExp _savingsLine = _re(
    r'^\W*(?:usted\s+|ud\.?\s+|hoy\s+)?(?:ahorro|ahorraste|ahorra)\b|'
    r'^\W*(?:su|tu|total)\s+ahorro\b|\byou\s+saved\b|'
    r'^\W*(?:total\s+|your\s+)?savings\b',
  );

  /// Whether the row is a discount line of the bill rather than a promise:
  /// "DESCUENTO 10% EN TU PROXIMA COMPRA MAYOR A \$200.00" is an offer.
  static bool _isDiscountLine(String l) =>
      _discountLine.hasMatch(l) &&
      _amountAt(l) != null &&
      !_nextVisit.hasMatch(l) &&
      !_condition.hasMatch(l);

  static ReceiptNote? _discountNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      if (!_isDiscountLine(l)) continue;
      final amount = _amountAt(l)!;
      if (amount.minor == 0) continue;
      // "PROMO 2X1 CERVEZA 90.00" is an item sold at its promotion price;
      // only "DESCUENTO" is a discount without a minus sign.
      final word = _discountLine.firstMatch(l)![1]!;
      if (!amount.negative && !_discountWordAtStart.hasMatch(word)) continue;
      final percent = RegExp(r'(\d{1,2})(?:[.,]\d+)?\s?%').firstMatch(l)?[1];
      return ReceiptNote(
        ReceiptNoteKind.discount,
        'Discount already applied: '
            '${percent == null ? '-${amount.text}' : '$percent% (-${amount.text})'}',
        detail: 'The amount paid is after this discount.',
        printed: t.raw[i],
      );
    }
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      if (!_savingsLine.hasMatch(l)) continue;
      final amount = _amountAt(l);
      if (amount == null || amount.minor == 0) continue;
      return ReceiptNote(
        ReceiptNoteKind.discount,
        'Savings on this receipt: ${amount.text}',
        detail: 'The amount paid is after these savings.',
        printed: t.raw[i],
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Exchange rate
  // ---------------------------------------------------------------------

  /// "TIPO DE CAMBIO 17.25", "TASA BCV: 36,50", "EXCHANGE RATE: 1 USD =
  /// 17.2500 MXN". The abbreviation "TC" is left alone: it is as often a
  /// credit card or a transaction code.
  static final RegExp _rateLabel = _re(
    r'(?:tipo\s+de\s+cambio|tasa\s+(?:de\s+cambio|bcv|del\s+dia|oficial|'
    r'de\s+conversion)|exchange\s+rate|conversion\s+rate)\b\s*[:=]?\s*(.*)$',
  );
  static final RegExp _rateEquation =
      RegExp(r'^1\s*[A-Z]{3}\s*=\s*\d[\d.,]*\s*[A-Z]{3}\b');
  static final RegExp _rateNumber =
      RegExp(r'(?<![\d.,/-])(\d{1,7}[.,]\d{2,6})(?![\d/-])');

  static ReceiptNote? _exchangeRateNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final rest = _rateLabel.firstMatch(t.plain[i])?[1];
      if (rest == null) continue;
      final rate =
          _rateEquation.firstMatch(rest)?[0] ?? _rateNumber.firstMatch(rest)?[1];
      // A rate of nothing, or of one to one, says nothing.
      if (rate == null || RegExp(r'^[01][.,]0+$').hasMatch(rate)) continue;
      return ReceiptNote(
        ReceiptNoteKind.exchangeRate,
        'Exchange rate on the receipt: $rate',
        detail: 'Useful when the claim is in another currency.',
        printed: t.raw[i],
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Offers for next time
  // ---------------------------------------------------------------------

  static final RegExp _survey = _re(
    r'encuesta|survey|opinion|feedback|cuentanos|(tu|su)\s+experiencia|'
    r'tell\s+us|califica',
  );

  /// Something free that is on offer: not "LLAMA GRATIS AL 800", "WIFI
  /// GRATIS", "DUTY FREE" or "GLUTEN FREE".
  static final RegExp _free = _re(
    r'(?<!(?:llam\w{1,4}|linea|lada|marca\w{0,2}|telefono|wi-?\s?fi|'
    r'estacionamiento|envio|entrega)\s)\bgratis\b(?!\s+al?\s+\d)|'
    r'(?<!(?:duty|gluten|sugar|toll|tax|fat|lactose|dairy|alcohol|nut|call)'
    r'[ -])\bfree\b(?!\s*(?:wi-?\s?fi|shipping|delivery|parking|refill))',
  );
  static final RegExp _discountWord = _re(
    r'descuento|\bdesc\b|\bdscto\b|\bdto\b|discount|%\s*off\b|rebaja',
  );
  static final RegExp _prize = _re(
    r'sorteo|\brifa\b|premio|prize\s+draw|sweepstakes?|\bwin\b|\bgana\b|'
    r'\bganar\b',
  );
  static final RegExp _twoForOne = _re(r'\b2\s?x\s?1\b');
  static final RegExp _points = _re(r'\bpuntos\b|\bpoints\b');
  static final RegExp _nextVisit = _re(
    r'(proxim[ao]|siguiente|next)\s+(visita|compra|consumo|pedido|purchase|'
    r'visit|order)',
  );

  /// "LO ESPERAMOS EN SU PROXIMA VISITA": a goodbye, not an offer.
  static final RegExp _farewell = _re(
    r'(esper\w+|vuelv\w+|regres\w+|hasta|see\s+you|come\s+back|visit\s+us)\b'
    r'[^.]{0,30}?(proxim[ao]|siguiente|next|pronto)',
  );

  /// "PRESENTA ESTE TICKET Y OBTEN", "CUPON VALIDO POR", "redeem", "with
  /// this receipt": the wording of something being given. "BUY ONE GET ONE
  /// FREE" on an item is how it was sold, not an offer.
  static final RegExp _offerCue = _re(
    r'\bobten\w*|\brecib[ae]\b|llevate|canje\w+|valido\s+por|\bcupon\b|'
    r'coupon|presenta\w*\s+(este|tu|su)\s+(ticket|cupon|recibo|comprobante)|'
    r'con\s+este\s+(ticket|cupon)|\bredeem|bring\s+this|present\s+this|'
    r'with\s+this\s+(receipt|coupon)|disfruta|te\s+regalamos',
  );

  /// An advert says when ("MARTES 2X1 EN PIZZAS"); an item sold two for one
  /// does not.
  static final RegExp _onDays = _re(
    r'\b(lunes|martes|miercoles|jueves|viernes|sabados?|domingos?|'
    r'mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?|'
    r'sundays?)\b|todos\s+los|every\s+',
  );

  /// A row that could start an offer.
  static final RegExp _benefit = _re(
    r'descuento|\bdesc\b|discount|\bgratis\b|\bfree\b|\b2\s?x\s?1\b|sorteo|'
    r'\brifa\b|premio|prize|sweepstake|\bgana\b|\bwin\b|\d{1,2}\s?%',
  );

  static final RegExp _validUntil = _re(
    r'(?:vigencia|valid[oa]\s+hasta|vence|vencimiento|'
    r'valid\s+(?:until|thru|through|till)|expires?)\s*(?:el\s+|al\s+|on\s+)?'
    r':?\s*(\d{1,2}\s?[/.-]\s?\d{1,2}\s?[/.-]\s?\d{2,4}|'
    r'\d{1,2}\s+(?:de\s+)?[a-z]{3,10}\.?\s+(?:de\s+|del\s+)?\d{4})',
  );

  /// What a paragraph offers, or null when it only looks like an offer: a
  /// benefit must come with how to get it (a survey, next visit, "presenta
  /// este ticket").
  static String? _offerTitle(String text) {
    final free = _free.hasMatch(text);
    final discount = _discountWord.hasMatch(text);
    final next = _nextVisit.hasMatch(text) && !_farewell.hasMatch(text);
    if (_survey.hasMatch(text)) {
      if (free) {
        return 'Answer the survey for something free${next ? ' next visit' : ''}';
      }
      if (_prize.hasMatch(text)) return 'Survey with a prize draw';
      // A survey with nothing in it for the customer is not worth a note.
      return discount || _points.hasMatch(text)
          ? 'Survey offer on the receipt'
          : null;
    }
    // Words from the totals ("DESCUENTO" over "CUPON") are not a sentence.
    if (text.split(' ').length < 4) return null;
    final given = next || _offerCue.hasMatch(text);
    if (free && given) {
      return 'Free item offer${next ? ' for your next visit' : ''}';
    }
    if (discount && given) {
      final percent = RegExp(r'(\d{1,2})\s?%').firstMatch(text)?[1];
      return 'Discount offer${percent == null ? '' : ': $percent%'}'
          '${next ? ' for your next visit' : ''}';
    }
    if (_twoForOne.hasMatch(text) && _onDays.hasMatch(text)) {
      return '2x1 promotion';
    }
    return null;
  }

  static ReceiptNote? _offerNote(_Rows t, List<_Topic?> topics) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      // A discount already taken off this bill is in the amounts, and a
      // percentage in a row about the tip is the tip's.
      if (!_benefit.hasMatch(l) || _isDiscountLine(l)) continue;
      if (topics[i] != null && topics[i] != _Topic.promo) continue;
      final paragraph = _paragraph(t, topics, i, _Topic.promo);
      final title = _offerTitle(_join(t.text, paragraph));
      if (title == null) continue;
      // The survey's address and the coupon's validity usually follow.
      final near = [...paragraph];
      for (var j = paragraph.last + 1;
          j < t.length && j <= i + 3;
          j++) {
        if (topics[j] != null && topics[j] != _Topic.promo) break;
        near.add(j);
      }
      final web = _webIn(near.map((j) => t.plain[j]));
      final until = _validUntil.firstMatch(_join(t.text, near))?[1];
      final detail = [
        if (web != null) 'Online: $web',
        if (until != null) 'Valid until: $until',
      ];
      return ReceiptNote(
        ReceiptNoteKind.offer,
        title,
        detail: detail.isEmpty ? null : detail.join('\n'),
        printed: _join(t.raw, paragraph),
      );
    }
    return _pointsNote(t);
  }

  static const String _number = r'(\d[\d.,]*\d|\d)';
  static final Map<String, RegExp> _pointsLines = {
    'Accumulated': _re(
      r'(?:puntos|pts)\s+acumulados(?:\s+(?:en|de|por)\s+(?:esta|tu|su)\s+'
              r'compra)?\s*:?\s*' +
          _number,
    ),
    'Earned': _re(
      r'(?:puntos|pts)\s+(?:ganados|obtenidos|generados|(?:de\s+)?esta\s+'
              r'compra)\s*:?\s*' +
          _number +
          r'|points\s+earned\s*:?\s*' +
          _number,
    ),
    'Balance': _re(
      r'(?:saldo|total|balance)\s+(?:de\s+|en\s+|actual\s+)?(?:puntos|points)'
              r'\s*:?\s*' +
          _number +
          r'|(?:puntos|points)\s+(?:disponibles|totales|balance)\s*:?\s*' +
          _number,
    ),
  };

  /// "PUNTOS ACUMULADOS: 120", "SALDO DE PUNTOS: 1,540": loyalty points
  /// with their numbers; an invitation to collect them says nothing.
  static ReceiptNote? _pointsNote(_Rows t) {
    final lines = <String>[];
    final printed = <String>[];
    for (final entry in _pointsLines.entries) {
      for (var i = 0; i < t.length; i++) {
        final m = entry.value.firstMatch(t.text[i]);
        if (m == null) continue;
        lines.add('${entry.key}: ${m[1] ?? m[2]}');
        printed.add(t.raw[i]);
        break;
      }
    }
    if (lines.isEmpty) return null;
    return ReceiptNote(
      ReceiptNoteKind.offer,
      'Rewards points',
      detail: lines.join('\n'),
      printed: printed.join(' '),
    );
  }

  // ---------------------------------------------------------------------
  // Wi-Fi
  // ---------------------------------------------------------------------

  static final RegExp _wifi =
      _re(r'wi-?\s?fi\b|\bwlan\b|\bssid\b|\binternet\b');

  /// "COMPRA POR INTERNET", "INTERNET 24 HRS 150.00": bought, not offered.
  static final RegExp _notWifi =
      _re(r'(por|via|en|de)\s+internet|internet\s+(banking|sales|order)');

  /// "Password: Secret123", "CLAVE WIFI: cafe2026", "Access code: 48213",
  /// or the label with the password on the next row. "CLAVE DE RASTREO" and
  /// "PASS TYPE" are labels of something else.
  static final RegExp _password = _re(
    r'\b(?:password|contrasena|clave|passcode|pass|pwd|pw|access\s+code|'
    r'codigo\s+de\s+acceso|key)\b'
    r'(?:\s+(?:de\s+|del\s+|for\s+)?(?:la\s+)?(?:wi-?\s?fi|internet|red|'
    r'network))?\s*(?:[:=]\s*(\S+)?|$)',
  );
  static final RegExp _networkLabel =
      _re(r'\b(?:red|ssid|network|nombre)\s*[:=]\s*(.+)$');
  static final RegExp _networkAfterWifi =
      _re(r'(wi-?\s?fi|internet)\s*([:=]\s*|\s+)(.+)$');
  static final RegExp _notANetwork = _re(
    r'^(gratis|free|gratuito|para|clientes|disponible|available|zone|zona|'
    r'network|red|on|en)$',
  );

  /// The network's name on [row], if it gives one: "Red: CAFE_EJEMPLO",
  /// "WIFI: EjemploGuest PW: ...", "Internet CLIENTES-WIFI".
  static String? _networkOn(String row, {required bool anchor}) {
    String? name;
    var labelled = true;
    final label = _networkLabel.firstMatch(row);
    if (label != null) {
      name = label[1];
    } else if (anchor) {
      final m = _networkAfterWifi.firstMatch(row);
      final password = _password.firstMatch(row);
      // "CLAVE WIFI: cafe2026": the word belongs to the password's label.
      if (m == null ||
          (password != null &&
              password.start < m.start &&
              password.end > m.start + m[1]!.length)) {
        return null;
      }
      name = m[3];
      labelled = m[2]!.trim().isNotEmpty;
    }
    if (name == null) return null;
    final password = _password.firstMatch(name);
    if (password != null) name = name.substring(0, password.start);
    name = name.trim();
    if (name.isEmpty || name.length > 30 || _notANetwork.hasMatch(name)) {
      return null;
    }
    return labelled || !name.contains(' ') ? name : null;
  }

  static ReceiptNote? _wifiNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final row = t.plain[i];
      if (!_wifi.hasMatch(row) || _notWifi.hasMatch(row) ||
          _price.hasMatch(row)) {
        continue;
      }
      String? password;
      var last = i;
      for (var j = i; j < t.length && j <= i + 2 && password == null; j++) {
        final m = _password.firstMatch(t.plain[j]);
        if (m == null) continue;
        password = m[1];
        last = j;
        // "PASSWORD:" with the password alone on the row under it.
        if (password == null &&
            j + 1 < t.length &&
            RegExp(r'^\S{4,32}$').hasMatch(t.plain[j + 1])) {
          password = t.plain[j + 1];
          last = j + 1;
        }
      }
      if (password == null) continue;
      String? network;
      for (var j = i; j <= last && network == null; j++) {
        network = _networkOn(t.plain[j], anchor: j == i);
      }
      return ReceiptNote(
        ReceiptNoteKind.wifi,
        'Wi-Fi password',
        detail: [
          if (network != null) 'Network: $network',
          'Password: $password',
        ].join('\n'),
        printed: [for (var j = i; j <= last; j++) t.raw[j]].join(' '),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Toilet and door codes
  // ---------------------------------------------------------------------

  static final RegExp _toilet =
      _re(r'sanitario|\bbanos?\b|\bwc\b|restroom|toilet|\baseos\b');
  static final RegExp _door = _re(
    r'\b(door|gate|entry)\s+code\b|'
    r'\b(codigo|clave)\s+(de\s+)?(la\s+)?(puerta|entrada)\b',
  );

  /// The wording of a code being given: a number near "BAÑOS" in an address
  /// or on "PAPEL SANITARIO 400 HOJAS" is not one.
  static final RegExp _codeCue = _re(
    r'codigo|\bcode\b|clave|tecle[ae]|marque|\bmarca\b|digit[ae]|'
    r'acce(so|der|ss)|\bpin\b|password|contrasena|combinacion|\benter\b|'
    r'\bpress\b',
  );
  static final RegExp _codeAtEnd = RegExp(r'(?<![\w.,])(\d{3,6}\s?[#*]?)\s*$');
  static final RegExp _codeAlone = RegExp(r'^\W*(\d{3,6}\s?[#*]?)\s*$');

  static ReceiptNote? _toiletNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      final door = _door.hasMatch(l);
      if (!door && !(_toilet.hasMatch(l) && _codeCue.hasMatch(l))) continue;
      if (_price.hasMatch(l)) continue;
      var code = _codeAtEnd.firstMatch(l)?[1];
      var rows = [i];
      if (code == null && i + 1 < t.length) {
        code = _codeAlone.firstMatch(t.text[i + 1])?[1];
        rows = [i, i + 1];
      }
      if (code == null) continue;
      return ReceiptNote(
        ReceiptNoteKind.toilet,
        '${door ? 'Door' : 'Toilet'} code: ${code.replaceAll(' ', '')}',
        printed: _join(t.raw, rows),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Parking
  // ---------------------------------------------------------------------

  static final RegExp _parkingWord =
      _re(r'estacionamiento|\bparqueo\b|parqueadero|\bparking\b');

  /// "CON SELLO DE CAJA", "SELLA TU BOLETO", "PARKING VALIDATION".
  static final RegExp _stamp = _re(
    r'\bsell[aeo]\b|\bsellar\b|'
    r'\bvalid(a|e|ar|alo|acion|ation|ate)\b|\bstamp',
  );
  static final RegExp _freeOfCharge =
      _re(r'\bgratis\b|\bfree\b|cortesia|sin\s+costo');
  static final RegExp _hours = _re(r'(\d{1,2})\s*(?:horas?|hrs?|hours?)\b');

  /// Parking the shop pays for: free hours, or the ticket stamped at the
  /// till. A car park's own receipt says nothing.
  static ReceiptNote? _parkingNote(_Rows t) {
    for (var i = 0; i < t.length; i++) {
      if (!_parkingWord.hasMatch(t.text[i])) continue;
      // The row itself, then with the row its sentence wraps onto or from;
      // the reading that gives both the hours and the stamp is the best.
      ({List<int> rows, bool stamp, String? hours})? best;
      for (final rows in [
        [i],
        if (i + 1 < t.length && _prose(t.text[i + 1])) [i, i + 1],
        if (i > 0 && _prose(t.text[i - 1])) [i - 1, i],
      ]) {
        final text = _join(t.text, rows);
        final stamp = _stamp.hasMatch(text);
        final hours = _freeOfCharge.hasMatch(text)
            ? _hours.firstMatch(text)?.group(1)
            : null;
        if (!stamp && hours == null) continue;
        if (best == null || (stamp && hours != null)) {
          best = (rows: rows, stamp: stamp, hours: hours);
        }
        if (stamp && hours != null) break;
      }
      if (best == null) continue;
      final (:rows, :stamp, :hours) = best;
      final free = hours == null
          ? null
          : '$hours ${hours == '1' ? 'hour' : 'hours'} free';
      return ReceiptNote(
        ReceiptNoteKind.parking,
        free == null
            ? 'Parking validation available'
            : 'Parking: $free${stamp ? ' with validation' : ''}',
        detail: stamp ? 'Have the parking ticket stamped at the till.' : null,
        printed: _join(t.raw, rows),
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Returns and warranty
  // ---------------------------------------------------------------------

  /// "PRECIOS SUJETOS A CAMBIOS", "CASA DE CAMBIOS", "TIPO DE CAMBIO":
  /// changes and exchange of money, not of goods.
  static final RegExp _otherChange = _re(
    r'sujet\w+\s+a\s+cambios?|casas?\s+de\s+cambios?|tipo\s+de\s+cambio',
  );
  static final RegExp _noReturns = _re(
    r'\bno\s+(se\s+)?(acepta\w*|hay|hacemos|realiza\w*|efectua\w*|'
    r'admite\w*|aplica\w*)\s+[^.]{0,20}?(cambios|devoluci|reembols)|'
    r'\bsin\s+(cambios|devoluci)|\bno\s+(refunds?|returns?|exchanges?)\b|'
    r'no\s+reembolsable|non-?\s?refundable|all\s+sales\s+(are\s+)?final',
  );

  /// "NO SE ACEPTAN DEVOLUCIONES SIN TICKET", "NO HAY CAMBIOS EN MERCANCIA
  /// DE OFERTA": a condition, not a refusal of all returns.
  static final RegExp _unless = _re(
    r'\bsin\s+(su\s+|el\s+|tu\s+)?(ticket|comprobante|recibo|nota|etiqueta|'
    r'empaque)|without\s+(a\s+|the\s+)?receipt|despues\s+de|\bafter\b|'
    r'(cambios|devoluciones|reembolsos|refunds|returns|exchanges)\s+'
    r'(en|de|para|sobre|on|for)\s+\w{4,}',
  );
  static final RegExp _warrantyWord = _re(r'garantia|warranty');
  static final RegExp _warranty = _re(
    r'(?:garantia|warranty)\s*:?\s*(?:de\s+|of\s+)?(\d{1,3})\s*'
    r'(mes(?:es)?|dias?|anos?|months?|years?|days?)\b|'
    r'(\d{1,3})\s*(mes(?:es)?|dias?|anos?|months?|years?|days?)\s+'
    r'(?:de\s+garantia|warranty)',
  );

  /// The wording of a policy: "CON TICKET", "UNICAMENTE", "accepted".
  static final RegExp _policy = _re(
    r'con\s+(su\s+|el\s+|tu\s+)?(ticket|comprobante|recibo|nota)|'
    r'presenta\w*|unicamente|\bsolo\b|solamente|\bonly\b|accepted|politica|'
    r'policy|etiqueta|empaque|original',
  );

  static String _period(String n, String unit) {
    final u = unit.toLowerCase();
    final name = u.startsWith('m')
        ? 'month'
        : u.startsWith('d')
            ? 'day'
            : 'year';
    return '$n ${n == '1' ? name : '${name}s'}';
  }

  static ReceiptNote? _returnsNote(_Rows t, List<_Topic?> topics) {
    for (var i = 0; i < t.length; i++) {
      final l = t.text[i];
      if (!_returnsWord.hasMatch(l) || _otherChange.hasMatch(l)) continue;
      final paragraph = _paragraph(t, topics, i, _Topic.returns);
      final text = _join(t.text, paragraph);
      String? title;
      if (_warrantyWord.hasMatch(l)) {
        final m = _warranty.firstMatch(text);
        if (m != null) {
          title = 'Warranty: ${_period(m[1] ?? m[3]!, m[2] ?? m[4]!)}';
        }
      } else if (_noReturns.hasMatch(text) && !_unless.hasMatch(text)) {
        title = 'No returns or refunds';
      } else {
        final spans = _spans(text);
        if (spans.isNotEmpty) {
          title = 'Returns or exchanges within '
              '${spans.first.n} ${spans.first.unit}';
        } else if (_policy.hasMatch(text) || _noReturns.hasMatch(text)) {
          title = 'Returns policy printed on the receipt';
        }
      }
      if (title == null) continue;
      return ReceiptNote(
        ReceiptNoteKind.returns,
        title,
        printed: _join(t.raw, paragraph),
      );
    }
    return null;
  }
}

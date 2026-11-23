import 'receipt_labels.dart';
import 'text_normaliser.dart';

/// For receipts that are not meals (taxis, hotels, fees…): the lines worth
/// translating, which is everything with words in it, minus reference
/// numbers, web addresses and scanning noise.
class ReceiptTextLines {
  ReceiptTextLines._();

  /// Web and e-mail addresses and social-media names. A bare "@" is a unit
  /// price ("3 @ 12.50", "@\$390.00"), not an address.
  static final RegExp _web = RegExp(
    r'www\.|https?:|\.(com|mx|net|org|gob|co|ve|sv)\b|'
    r'\b[a-z0-9-]{3,}\.(gt|hn|ni|cr|pa|do|pe|cl|ar|br|es|uk|us|io|app|info)\b|'
    r'[a-z0-9._-]+@[a-z0-9-]+\.[a-z]{2,}|(^|\s)@[a-z_]{3,}',
    caseSensitive: false,
  );

  /// Lines of numbers for the bank or the tax office, not for the claim:
  /// card-terminal references ("AFILIACION: 1000001", "AID: A0000000031010"),
  /// tax IDs ("RFC XXX010101AB1", "NIT: 1234567-8", "RIF: J-00000000-0"),
  /// tax-authority boilerplate ("SELLO DIGITAL…", "RESOLUCION DIAN No.…",
  /// "REGIMEN GENERAL DE LEY", "GIRO: VENTA DE COMBUSTIBLES") and telephone
  /// numbers.
  static final RegExp _reference = RegExp(
    r'^(afiliaci[oó]n|terminal(\s*id)?|autorizaci[oó]n|aut\.|aut\s*[:#\d]|'
    r'id\s*pbx|tr[.,]?\s*no|referencia|ref\.?\s*[:#\d]|'
    r'n[uú]mero\s*de\s*control|num\.?\s*tarjeta|no\.?\s*tarjeta|aid\b|arqc|'
    r'rrn\b|tvr\b|tsi\b|atc\b|stan\b|trace\b|auth\b|app\s*(label|name|id)\b|'
    r'tc\s*:\s*[0-9a-f]{8}|lote\b|secuencia\b|oper\.?\s*\d|'
    r'aprobaci[oó]n\b|aprob\.?\s*[:#]?\s*\d|c[oó]d\.?\s*aprob|'
    r'(no|n[uú]m|n[uú]mero|nro|c[oó]d|c[oó]digo|clave)\.?\s*(de\s+)?'
    r'(autorizaci[oó]n|aprobaci[oó]n|afiliaci[oó]n|comercio|referencia|'
    r'serie|certificado|cuenta|operaci[oó]n|transacci[oó]n|rastreo|'
    r'registro|resoluci[oó]n|generaci[oó]n|dte|acceso)\b|'
    r'folio\s*fiscal|serie\b|certificado|sello\b|cadena\s+original|'
    r'uuid\b|cufe\b|cude\b|resoluci[oó]n\b|rango\s+autorizado|prefijo\b|'
    r'numeraci[oó]n\s+(autorizada|habilitada)|permiso\b|licencia\b|'
    r'registro\s+(fiscal|federal|sanitario|mercantil|patronal)|'
    r'uso\s+(de\s+|del\s+)?cfdi|lugar\s+de\s+expedici[oó]n|'
    r'fecha(\s+y\s+hora)?\s+de\s+(certificaci[oó]n|timbrado)|'
    r'(este\s+documento\s+es\s+una\s+)?representaci[oó]n\s+impresa|'
    r'actividad\s+econ[oó]mica|giro\s*:|seniat\b|'
    r'rfc\b|r\.f\.c|n\.?i\.?t\.?(?![a-zà-ÿ])|n\.?r\.?c\.?(?![a-zà-ÿ])|'
    r'r\.?i\.?f\.?(?![a-zà-ÿ])|dui\b|ruc\b|rtn\b|curp\b|'
    r'persona\s+(mor\w*|f[ií]sica)|'
    r'(tels?|tel[eé]fonos?|fax|cel|celular|whats\s?app|pbx|lada)\.?\s*'
    r'[:.]?\s*[(+]?\d[\d\s()+-]{6,})|'
    r'\br[eé]g\w{1,2}men\b',
    caseSensitive: false,
  );

  /// A masked card number ("534985******4983", "TARJETA: ****4983",
  /// "XXXX-XXXX-XXXX-1234").
  static final RegExp _cardNumber = RegExp(
    r'(?:\d{4,6}[\s-]?)?(?:[*•]{2,}|[Xx]{4,})'
    r'(?:[\s-]?(?:[*•]+|[Xx]{2,}))*[\s-]?\d{0,4}',
  );

  /// A code with no meaning to a reader: a UUID ("A1B2C3D4-E5F6-4789-ABCD-
  /// 0123456789AB") or one unbroken string longer than any word (a digital
  /// seal, a hash).
  static final RegExp _code = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$|'
    r'^\S{25,}$',
    caseSensitive: false,
  );

  /// "TERMINAL: 12345678 FECHA: 14/09/26": where the second of two
  /// labelled columns on one row begins.
  static final RegExp _columnBreak = RegExp(
    r'(?<=[\d)*]\S*)\s+'
    r'(?=(?:[A-Za-zÀ-ÿ.°#/]+\s){0,3}[A-Za-zÀ-ÿ.°#/]+\s?:)',
  );

  static final RegExp _price = RegExp(r'\d[.,]\d{2}(?!\d)');

  /// Three or more of the same mark in a row, with or without gaps: dot
  /// leaders ("....", ". . . ."), rules ("----", "====", "____"), stars.
  static final RegExp _leaders = RegExp(r'([.\-_=*~])(?:\s?\1){2,}');

  /// A figure a reader takes in at a glance: a date ("14/09/2026",
  /// "2026-09-14"), a time ("12:49:05"), a percentage ("16%") or an amount
  /// ("1,850.00").
  static final RegExp _figure = RegExp(
    r'(?<![\d/.-])(?:\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?|'
    r'\d{4}-\d{2}-\d{2})(?![\d/-])|'
    r'(?<![\d:])\d{1,2}:\d{2}(?::\d{2})?(?![\d:])|'
    r'(?<![\d.,])\d{1,3}(?:[.,]\d+)?\s?%|'
    r'(?<![\d.,])\d{1,3}(?:[.,\s]?\d{3})*[.,]\d{2}(?![\d.,])',
  );

  /// Lines of an address: kept as printed, since translating street and
  /// district names gives nonsense ("Forests of the Lomas"). Postcodes;
  /// street words at the start ("AV. REFORMA 222", Colombia's "CRA 7 #
  /// 71-21", Guatemala's "4A AVENIDA 12-59 ZONA 10" and "KM 14.5 CARRETERA
  /// A EL SALVADOR"); street abbreviations with their dot anywhere ("…,
  /// COL. DEL VALLE"); boroughs and municipalities.
  static final RegExp _address = RegExp(
    r'\bc\.?\s?p\.?\s?:?\s?\d{5}\b|,\s*\d{5}\s*$|'
    r'^(paseo|calle|av\.?|avda\.?|avenida|blvd\.?|boulevard|bulevar|calz\.?|'
    r'calzada|carretera|carr\.|carrera|transversal|diagonal|autopista|'
    r'col\.?|colonia|fracc\.?|fraccionamiento|urb\.?|urbanizaci[oó]n|'
    r'barrio|residencial|prol\.?|prolongaci[oó]n|privada|priv\.|circuito|'
    r'perif[eé]rico|esq\.?|esquina|entre|edif\.?|edificio|torre|local|'
    r'centro\s+comercial|plaza\s+comercial|zona|rua|travessa)\s|'
    r'^(cll?|cra|kra|kr|cr|tv|dg|ak|ac)\.?\s?\d+\s?[a-z]?\s?(#|no\.?|n°)|'
    r'^\d{1,2}\s?[aª]?\.?\s?(av\.?|avenida|calle)(\s|$)|'
    r'\bzona\s\d{1,2}\b|^km\.?\s?\d|'
    r'\b(av|avda|blvd|calz|col|fracc|urb|prol|esq|carr|edif|mza|depto)\.\s?\S|'
    r'\bcarretera\s+(a|al|federal|nacional|panamericana|interamericana)\b|'
    r'\b(ciudad\s+de\s+m[eé]?xico|cdmx|m[eé]xico,?\s*d\.?\s?f\.?)\s*$|'
    r'\b(alc(ald[ií]a|\.)|del(egaci[oó]n|\.)|mpio\.?|municipio|edo\.)\s',
    caseSensitive: false,
  );

  /// "GUADALAJARA, JALISCO", "MIXCO, GUATEMALA", "ANTIGUO CUSCATLAN, LA
  /// LIBERTAD": a town and its state, department or country. Matched on
  /// the line in lower case without accents.
  static final RegExp _townAndState = RegExp(
    r',\s*(aguascalientes|baja california( sur)?|campeche|chiapas|chihuahua|'
    r'coahuila|colima|durango|guanajuato|guerrero|hidalgo|jalisco|mexico|'
    r'estado de mexico|michoacan|morelos|nayarit|nuevo leon|oaxaca|puebla|'
    r'queretaro|quintana roo|san luis potosi|sinaloa|sonora|tabasco|'
    r'tamaulipas|tlaxcala|veracruz|yucatan|zacatecas|ags|bcs?|chis|chih|'
    r'coah|dgo|gto|gro|hgo|jal|mex|mich|nay|n\.? ?l|oax|pue|qro|q\.? ?roo|'
    r's\.? ?l\.? ?p|tamps|tlax|yuc|zac|guatemala|sacatepequez|'
    r'quetzaltenango|escuintla|peten|izabal|alta verapaz|baja verapaz|'
    r'chimaltenango|huehuetenango|solola|retalhuleu|suchitepequez|'
    r'san marcos|quiche|totonicapan|zacapa|chiquimula|jalapa|jutiapa|'
    r'santa rosa|el progreso|san salvador|la libertad|santa ana|'
    r'san miguel|sonsonate|usulutan|ahuachapan|la paz|la union|'
    r'chalatenango|cuscatlan|morazan|san vicente|cabanas|el salvador|'
    r'venezuela|distrito capital|miranda|zulia|carabobo|aragua|'
    r'anzoategui|tachira|merida|nueva esparta|caracas|colombia|'
    r'bogota( d\.? ?c)?|d\.? ?c|antioquia|cundinamarca|valle del cauca|'
    r'atlantico|honduras|costa rica|panama|nicaragua|c\.? ?a)\.?\s*$',
  );

  /// A company's legal name ("… S DE RL DE CV", "… SA DE CV", Guatemala's
  /// "…, SOCIEDAD ANONIMA", Venezuela's "…, C.A.", Colombia's "… S.A.S.").
  static final RegExp _legalName = RegExp(
    r'\bde\s+c\.?\s?v\.?\s*$|\bs\.?\s?a\.?\s?p\.?\s?i\.?\b|'
    r'\bs\.?\s?a\.?\s?s\.?\s*$|\bs\.?\s?a\.?\s*$|\bs\.?\s?l\.?\s*$|'
    r'\bltda\.?\s*$|\bc\.\s?a\.?\s*$|\bs\.?\s?de\s+r\.?\s?l\.?\s*$|'
    r'\bsociedad\s+an[oó]nima\s*$',
    caseSensitive: false,
  );

  /// Indexes of [lines] to keep as printed, not translate: addresses
  /// (including a district line between two address lines) and legal
  /// company names. A line with a price is neither ("PASEO EN LANCHA
  /// 500.00" is something bought).
  static Set<int> asPrinted(List<String> lines) {
    bool isAddress(String line) =>
        !_price.hasMatch(line) &&
        (_address.hasMatch(line) ||
            _townAndState.hasMatch(
                TextNormaliser.stripDiacritics(line).toLowerCase()));
    final address = [for (final l in lines) isAddress(l)];
    final out = <int>{};
    for (var i = 0; i < lines.length; i++) {
      final between = i > 0 &&
          i + 1 < lines.length &&
          address[i - 1] &&
          address[i + 1] &&
          lines[i].contains(',');
      final legal =
          _legalName.hasMatch(lines[i]) && !_price.hasMatch(lines[i]);
      if (address[i] || between || legal) out.add(i);
    }
    return out;
  }

  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _letter = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ]');

  /// What is worth translating in [row]: the row without its card number
  /// and reference columns, or null when nothing is left.
  static String? _clean(String row) {
    var text = TextNormaliser.collapseSpaces(row);
    if (_web.hasMatch(text)) return null;
    // "534985******4983": the card number is cut out; "VISA CREDITO" or
    // "VISA" beside it stays. What is left of a row of stars and crosses
    // ("XX*** X*****" -> "XX X") goes with it.
    final unmasked =
        TextNormaliser.collapseSpaces(text.replaceAll(_cardNumber, ' '));
    if (unmasked != text) {
      text = unmasked
          .split(' ')
          .where((t) => !RegExp(r'^[Xx]+$').hasMatch(t))
          .join(' ');
    }
    // "TOTAL ......... 570.00", "*** COPIA ***", "FIRMA ________": dot
    // leaders, rules and rows of stars are layout, not text.
    text = TextNormaliser.collapseSpaces(text.replaceAll(_leaders, ' '));
    // "=====", "--*--": rules that OCR half-read as letters. The strokes
    // and dots of a date or an amount are not such symbols.
    final symbols = RegExp(r'[^\sA-Za-z0-9À-ÿ]')
        .allMatches(text.replaceAll(_figure, ''))
        .length;
    if (symbols > TextNormaliser.letterCount(text)) return null;
    text = text.split(' ').where((t) => !_code.hasMatch(t)).join(' ');
    // "TERMINAL: 12345678 FECHA: 14/09/26": a row of two columns is judged
    // column by column, so the date survives its neighbour.
    final columns = [
      for (final column in text.split(_columnBreak))
        if (!_reference.hasMatch(column)) column,
    ];
    text = columns.join(' ');
    final letters = TextNormaliser.letterCount(text);
    if (letters < 3) return null;
    // "IIIIIIII", "XXXXXX": a barcode or a row of crosses read as letters.
    final different = {
      for (final m in _letter.allMatches(text)) m[0]!.toLowerCase(),
    };
    if (letters >= 5 && different.length <= 2) return null;
    // A label with nothing after it ("BANCO EMISOR:") says nothing.
    if (text.endsWith(':')) return null;
    // Codes and references ("CAS020301462", "220000000000001") are single
    // tokens; real lines ("FECHA 2026-09-18 22:19") have words around them.
    final digits = _digit.allMatches(text).length;
    if (!text.contains(' ') && digits > letters) return null;
    // A barcode before an item's name ("7501055300075 AGUA 1L 12.00") does
    // not make the line a number, and neither do the date, the rate and the
    // amount around a word ("14/09/2026 IVA 16% 296.00").
    final counted = _digit
        .allMatches(text
            .replaceAll(RegExp(r'(?<!\d)\d{8,}(?!\d)'), '')
            .replaceAll(_figure, ''))
        .length;
    return counted <= letters * 2 + 4 ? text : null;
  }

  static bool isMeaningful(String row) => _clean(row) != null;

  /// A row that is only a figure: an amount, a date or a time ("\$570.00",
  /// "14/09/2026 12:49", "570.00 MXN").
  static final RegExp _bareValue = RegExp(
    r'^[($QqBsS./-]{0,5}\s?\d[\d\s.,:/-]*\)?'
    r'(\s?(mxn|m\.?n\.?|usd|gtq|cop|ves|hrs?|[ap]\.?\s?m\.?|%))?$',
    caseSensitive: false,
  );

  static bool _isBareValue(String row) {
    final text = TextNormaliser.collapseSpaces(row);
    return _bareValue.hasMatch(text) &&
        RegExp(r'[.,:/-]\d').hasMatch(text) &&
        _digit.allMatches(text).length <= 14;
  }

  /// A label waiting for its value: "TOTAL:", "FECHA:".
  static bool _isBareLabel(String row) {
    final text = TextNormaliser.collapseSpaces(row);
    return text.endsWith(':') &&
        !_digit.hasMatch(text) &&
        TextNormaliser.letterCount(text) >= 3 &&
        text.split(' ').length <= 4;
  }

  /// Whether the lone caption [row] and the figure [value] under it belong
  /// together: an amount under a money caption ("TOTAL" / "\$570.00",
  /// "EFECTIVO" / "200.00"), a date under "FECHA", a time under "HORA".
  static bool _awaits(String row, String value) {
    if (_digit.hasMatch(row) || !ReceiptLabels.isCaption(row)) return false;
    final caption = TextNormaliser.stripDiacritics(row).toLowerCase();
    final date = RegExp(r'\d[/-]\d').hasMatch(value);
    final time = RegExp(r'\d:\d\d').hasMatch(value);
    if (RegExp(r'^fecha\b').hasMatch(caption)) return date;
    if (RegExp(r'^hora\b').hasMatch(caption)) return time && !date;
    return _money.hasMatch(caption) &&
        _price.hasMatch(value) &&
        !date &&
        !time;
  }

  /// A line that is part of running text: long, wordy, no label or price.
  static bool _prose(String text) => text.length >= 20 && _wordy(text);

  /// Words only: no label, no price, hardly a digit.
  static bool _wordy(String text) =>
      !text.contains(':') &&
      !RegExp(r'\d[.,]\d{2}\b').hasMatch(text) &&
      _digit.allMatches(text).length <= 2;

  /// Meaningful rows in reading order, at most [limit] of them.
  ///
  /// - A label whose value landed on the next row ("TOTAL:" / "\$570.00",
  ///   "IMPORTE" / "\$118.00") takes it back.
  /// - A paragraph the printer wrapped over several lines
  ///   ("…INCONDICIONAL-" / "MENTE A PAGAR…") is joined back into one line,
  ///   so it is translated as a sentence and not in broken pieces.
  /// - A line repeated straight away, or a wordy line printed again further
  ///   down (the shop's name above the card slip), is given once.
  /// - Dot leaders and rules are taken out ("TOTAL ........ 570.00"), and a
  ///   row that only points at a web address goes with the address.
  /// - When there are more than [limit], totals, payment and priced lines
  ///   are the ones kept.
  static List<String> meaningful(List<String> rows, {int limit = 40}) {
    final texts = <String>[];
    final follows = <bool>[]; // the line is the row right after the last one
    var adjacent = false;
    var looseValue = false; // the row before was a figure with no label
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i];
      var used = 1;
      // The amount under its label. Not when labels and amounts come as two
      // blocks ("SUBTOTAL:" "IVA:" "TOTAL:" then three amounts): then nobody
      // can say which amount is whose.
      if (_isBareLabel(row) &&
          i + 1 < rows.length &&
          _isBareValue(rows[i + 1]) &&
          !(i > 0 && _isBareLabel(rows[i - 1])) &&
          !(i + 2 < rows.length && _isBareValue(rows[i + 2]))) {
        row = '$row ${rows[i + 1]}';
        used = 2;
      } else if (i + 1 < rows.length &&
          _isBareValue(rows[i + 1]) &&
          _awaits(row, rows[i + 1]) &&
          // Not when the figures are printed above their captions
          // ("570.00" / "TOTAL" / "600.00" / "EFECTIVO"), nor in two blocks.
          !looseValue &&
          !(i > 0 &&
              (_isBareLabel(rows[i - 1]) ||
                  ReceiptLabels.isCaption(rows[i - 1]))) &&
          !(i + 2 < rows.length && _isBareValue(rows[i + 2]))) {
        // "IMPORTE" / "\$118.00": the same with no colon, for a caption the
        // label dictionary knows and a figure of the kind it waits for.
        row = '$row ${rows[i + 1]}';
        used = 2;
      }
      looseValue = used == 1 && _isBareValue(row);
      final text = _clean(row);
      i += used - 1;
      if (text == null) {
        // "PARA FACTURAR INGRESE A" / "www.ejemplo.mx": the row that only
        // points at a web address goes with it.
        if (adjacent && _web.hasMatch(row) && _pointer.hasMatch(texts.last)) {
          texts.removeLast();
          follows.removeLast();
        }
        adjacent = false;
        continue;
      }
      if (texts.isNotEmpty && texts.last.toLowerCase() == text.toLowerCase()) {
        continue;
      }
      texts.add(text);
      follows.add(adjacent);
      adjacent = true;
    }

    final joined = _joinParagraphs(texts, follows);

    // The shop's name or "VENTA" printed again further down adds nothing.
    // A line with a number may be a second purchase of the same thing.
    final out = <String>[];
    final seen = <String>{};
    for (final line in joined) {
      final key = line.toLowerCase();
      if (!_digit.hasMatch(line) && !seen.add(key)) continue;
      out.add(line);
    }
    return _mostImportant(out, limit);
  }

  /// The end of a row that only leads up to what comes next: "… INGRESE A",
  /// "… AVISO DE PRIVACIDAD EN", "VISITANOS EN:".
  static final RegExp _pointer =
      RegExp(r'\s(a|al|en|a\s+la\s+p[aá]gina)\s?:?$', caseSensitive: false);

  /// Words that tie one printed line to the next in running text.
  static const Set<String> _endJoiners = {
    'de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'que', 'a', 'al', 'en', //
    'con', 'por', 'para', 'este', 'esta', 'su', 'sus', 'un', 'una', 'of',
    'the', 'and', 'to', 'for', 'with',
  };
  static const Set<String> _startJoiners = {
    'de', 'del', 'y', 'e', 'que', 'a', 'al', 'en', 'of', 'and', 'to',
  };

  /// Words that begin a new notice, never the middle of a sentence:
  /// "GRACIAS POR…", "CONSERVE SU…", "FIRMA".
  static const Set<String> _openers = {
    'gracias', 'conserve', 'guarde', 'vuelva', 'visite', 'visitanos', //
    'consulte', 'consulta', 'solicite', 'solicita', 'exija', 'pida',
    'recuerde', 'verifique', 'revise', 'presente', 'llame', 'llamanos',
    'siguenos', 'descarga', 'bienvenido', 'bienvenidos', 'estimado',
    'atencion', 'aviso', 'importante', 'original', 'copia', 'firma',
    'horario', 'telefono', 'tel', 'quejas', 'total', 'subtotal', 'fecha',
    'hora', 'autorizado', 'aprobado', 'aprobada', 'facture', 'facturacion',
  };

  static String _firstWord(String text) => text.split(' ').first;

  static String _bare(String word) => TextNormaliser.stripDiacritics(word)
      .toLowerCase()
      .replaceAll(RegExp('[^a-z]'), '');

  /// Joins the wrapped lines of [texts] back into sentences. [follows] says
  /// which lines came straight after the one before.
  ///
  /// Two lines belong together when the first ends in a hyphen, a comma or
  /// a joining word ("…DE APERTURA" / "DE CREDITO…"), or the second starts
  /// with a joining word or a small letter. Inside a paragraph of three or
  /// more lines that shows one such join, the other breaks are wraps too
  /// when the printer had no room for the next word; that also brings in
  /// the paragraph's short last line ("…TARJETAHABIENTE" / "TIENEN
  /// CELEBRADO."). A break the next word would have fitted into was made on
  /// purpose: a new notice ("GRACIAS POR SU COMPRA" / "VUELVA PRONTO").
  static List<String> _joinParagraphs(List<String> texts, List<bool> follows) {
    final out = <String>[];
    var i = 0;
    while (i < texts.length) {
      // The run of text lines from here: rows of running text, and the
      // short line that may end them.
      var end = i + 1;
      if (_prose(texts[i]) || texts[i].endsWith('-')) {
        while (end < texts.length && follows[end] && _prose(texts[end])) {
          end++;
        }
        if (end < texts.length &&
            follows[end] &&
            _wordy(texts[end]) &&
            (end + 1 >= texts.length ||
                !follows[end + 1] ||
                !_wordy(texts[end + 1]))) {
          end++;
        }
      }
      final run = texts.sublist(i, end);
      i = end;
      if (run.length == 1) {
        out.add(run.single);
        continue;
      }
      var width = 0;
      for (final line in run) {
        if (line.length > width) width = line.length;
      }
      // For each break: certainly a wrap, perhaps a wrap, or neither.
      final sure = <bool>[];
      final maybe = <bool>[];
      for (var k = 0; k + 1 < run.length; k++) {
        final line = run[k];
        final next = run[k + 1];
        final first = _firstWord(next);
        final noRoom = line.length + 1 + first.length > width;
        final hyphen = line.endsWith('-');
        final ended = RegExp(r'[.!?:;]$').hasMatch(line);
        final tied = _endJoiners.contains(_bare(line.split(' ').last)) &&
            !ended;
        final carriesOn = line.endsWith(',') ||
            (!ended &&
                RegExp(r'^[a-zà-ÿ]').hasMatch(next) &&
                RegExp(r'[a-zà-ÿ]').hasMatch(line));
        final leadsIn = _startJoiners.contains(_bare(first)) && noRoom;
        sure.add(hyphen || tied || carriesOn || leadsIn);
        maybe.add(noRoom && !ended && !_openers.contains(_bare(first)));
      }
      // Stretches of lines with no deliberate break between them.
      var start = 0;
      for (var k = 0; k < run.length; k++) {
        final last = k + 1 == run.length;
        if (!last && (sure[k] || maybe[k])) continue;
        final paragraph = k - start + 1 >= 3 &&
            sure.sublist(start, k).any((s) => s);
        var line = run[start];
        for (var j = start; j < k; j++) {
          if (paragraph || sure[j]) {
            line = line.endsWith('-')
                ? line.substring(0, line.length - 1) + run[j + 1]
                : '$line ${run[j + 1]}';
          } else {
            out.add(line);
            line = run[j + 1];
          }
        }
        out.add(line);
        start = k + 1;
      }
    }
    return out;
  }

  /// What a line says about money: totals, taxes, payment, change.
  static final RegExp _money = RegExp(
    r'\b(sub\s?total|total|importe|monto|i\.?v\.?a|impuestos?|propina|'
    r'efectivo|cambio|vuelto|pago|pagado|tarjeta|cr[eé]dito|d[eé]bito|saldo|'
    r'descuento|neto|valor|tarifa|peaje|cuota|pesos|quetzales|d[oó]lares|'
    r'bol[ií]vares)\b',
    caseSensitive: false,
  );

  /// How much a line matters to someone checking the claim: 3 for money
  /// lines ("TOTAL \$844.78", "FORMA DE PAGO: TARJETA DE CREDITO"), 2 for the
  /// heading and for lines with a price, a date or a label ("PRODUCTO:
  /// MAGNA"), 1 for other short lines, 0 for small print and addresses.
  static int _weight(List<String> lines, int index, Set<int> printed) {
    final line = lines[index];
    final hasNumber = _digit.hasMatch(line);
    final words = line.split(' ').length;
    // A label and its value, not a sentence with a colon in it.
    final labelled = line.contains(':') && (hasNumber || words <= 8);
    if (_money.hasMatch(line) &&
        (hasNumber || labelled || line.length <= 30)) {
      return 3;
    }
    if (index < 2) return 2;
    if (printed.contains(index)) return 0;
    if (_price.hasMatch(line) || labelled) return 2;
    if (hasNumber && words <= 8) return 2;
    return words <= 5 ? 1 : 0;
  }

  /// [lines] cut down to [limit], dropping the least important first (small
  /// print, addresses, then other wording, from the bottom up) and keeping
  /// the order of what stays. Totals and payment lines go last of all.
  static List<String> _mostImportant(List<String> lines, int limit) {
    if (lines.length <= limit) return lines;
    final printed = asPrinted(lines);
    final weights = [
      for (var i = 0; i < lines.length; i++) _weight(lines, i, printed),
    ];
    final dropped = <int>{};
    for (var weight = 0;
        weight <= 3 && lines.length - dropped.length > limit;
        weight++) {
      for (var i = lines.length - 1;
          i >= 0 && lines.length - dropped.length > limit;
          i--) {
        if (weights[i] == weight) dropped.add(i);
      }
    }
    return [
      for (var i = 0; i < lines.length; i++)
        if (!dropped.contains(i)) lines[i],
    ];
  }
}

import '../entities/enums.dart';
import 'amount_in_words.dart';
import 'text_normaliser.dart';

/// Decides whether a purchased item is a drink or food, from either the
/// wording on the receipt or its English translation. Anything not clearly a
/// drink is food. The user can change it on the translation screen.
class ItemClassifier {
  ItemClassifier._();

  static const Set<String> _drinkWords = {
    // English
    'drink', 'drinks', 'beverage', 'water', 'sparkling', 'still', 'juice',
    'lemonade', 'smoothie', 'shake', 'milkshake', 'soda', 'cola', 'coke',
    'sprite', 'fanta', 'pepsi', 'beer', 'lager', 'ale', 'wine', 'prosecco',
    'champagne', 'cocktail', 'margarita', 'mojito', 'michelada', 'whisky',
    'whiskey', 'vodka', 'gin', 'rum', 'tequila', 'mezcal', 'brandy', 'cider',
    'coffee', 'espresso', 'latte', 'cappuccino', 'americano', 'macchiato',
    'mocha', 'tea', 'chai', 'infusion', 'horchata', 'tonic', 'liqueur',
    'frappe', 'frappuccino', 'frapuccino', 'iced', 'cortado', 'matcha',
    'babyccino', 'refresher', 'chocolate caliente',
    // Spanish / Portuguese
    'bebida', 'bebidas', 'agua', 'jugo', 'zumo', 'limonada', 'naranjada',
    'licuado', 'batido', 'malteada', 'refresco', 'gaseosa', 'cerveza',
    'vino', 'cafe', 'te', 'coctel', 'ron', 'chela',
    'cervejas', 'cerveja', 'suco', 'refrigerante', 'vinho',
  };

  // Brand names that identify a drink on their own.
  static const List<String> _drinkPhrases = [
    'coca', 'pepsi', 'heineken',
  ];

  static ItemCategory classify(String original, [String translated = '']) {
    for (final text in [translated, original]) {
      final key = TextNormaliser.glossaryKey(text);
      if (key.isEmpty) continue;
      final words = key.split(' ');
      if (words.any(_drinkWords.contains)) return ItemCategory.drink;
      if (_drinkPhrases.any(words.contains)) return ItemCategory.drink;
    }
    return ItemCategory.food;
  }
}

/// Light clean-up of item wording before it goes to the translator.
class ItemWording {
  ItemWording._();

  static final Map<RegExp, String> _spanishAbbreviations = {
    // Card-slip terms the model gets wrong ("Handber card", "Box 1").
    RegExp(r'\btarjeta\s*habiente\b', caseSensitive: false):
        'titular de la tarjeta',
    RegExp(r'\bcaja\b(?=\s*:?\s*\d)', caseSensitive: false): 'caja registradora',
    RegExp(r'\btransacci\s?[oó]?\s?n\s?(?=electr)', caseSensitive: false):
        'transacción ',
    // "COLA" alone is the drink, not a queue; "PAPAS" at a fast-food till
    // are fries, not popes; "LLEVAR" on its own is a takeaway order.
    RegExp(r'(?<!(?:coca|refresco|de)[\s-]?)\bcola\b', caseSensitive: false):
        'refresco de cola',
    RegExp(r'\bpapas\s+fam\w*', caseSensitive: false): 'papas fritas familiares',
    RegExp(r'\bpapas\b(?=\s+(?:chicas?|medianas?|grandes?|gajo)\b|\s*$)',
        caseSensitive: false): 'papas fritas',
    RegExp(r'(?<!para\s)\bllevar\b', caseSensitive: false): 'para llevar',
    RegExp(r'\bbot\b', caseSensitive: false): 'botella',
    RegExp(r'\bens\b', caseSensitive: false): 'ensalada',
    RegExp(r'\bcerv\b', caseSensitive: false): 'cerveza',
    RegExp(r'\bhamb\b', caseSensitive: false): 'hamburguesa',
  };

  /// Words that a thermal printer's gaps make OCR split in two.
  static const Set<String> _splitWords = {
    'refresco', 'tarjeta', 'terminal', 'cerveza', 'hamburguesa', 'ensalada',
    'botella', 'propina', 'importe', 'servicio', 'consumo', 'factura',
    'electronica', 'aprobado', 'autorizacion', 'efectivo', 'americano',
    'capuchino', 'chocolate', 'malteada', 'limonada', 'naranjada', 'postre',
    'desayuno', 'comida', 'cena', 'bebida', 'orden', 'combo', 'helado',
  };

  /// Read errors fixed before translating and showing: a capital I read as
  /// a small L ("lced" -> "Iced", "lmporte" -> "Importe") and split words.
  static String tidy(String text) => rejoin(text.replaceAllMapped(
        RegExp(r'\bl(?=[cdfgkmnpqrsvwxz][a-z]{2})'),
        (_) => 'I',
      ));

  /// "REFRE SCO 887 ML" -> "REFRESCO 887 ML", "TARJE TA" -> "TARJETA": two
  /// pieces of a known word read apart are joined again.
  static String rejoin(String text) {
    final words = text.split(' ');
    final out = <String>[];
    for (var i = 0; i < words.length; i++) {
      if (i + 1 < words.length) {
        final joined = words[i] + words[i + 1];
        final key = TextNormaliser.glossaryKey(joined);
        if (words[i].length >= 2 &&
            words[i + 1].length >= 2 &&
            RegExp(r'^[A-Za-zÀ-ÿ]+$').hasMatch(joined) &&
            _splitWords.contains(key)) {
          out.add(joined);
          i++;
          continue;
        }
      }
      out.add(words[i]);
    }
    return out.join(' ');
  }

  /// "COCA ZERO BOT" -> "COCA ZERO botella": receipt abbreviations the
  /// on-device model cannot guess. Only Spanish is handled for now.
  static String expandAbbreviations(String text, String language) {
    if (language != 'es') return text;
    var out = text;
    _spanishAbbreviations.forEach((pattern, full) {
      out = out.replaceAll(pattern, full);
    });
    return out;
  }
}

/// Standard wording printed on receipts and card slips, with a fixed
/// translation: the on-device model mangles legal text ("For this promise I
/// force myself") and terse notices.
class KnownPhrases {
  KnownPhrases._();

  /// Legal clauses, recognised by how they begin: the rest of the paragraph
  /// is standard, whatever the bank or the line breaks.
  static final List<(RegExp, String)> _spanish = [
    (
      RegExp(r'^por\s+este\s+pagar[eé]\b', caseSensitive: false),
      'By this promissory note I unconditionally promise to pay to the order '
          'of the issuing bank the amount of this document. This note arises '
          'from the credit agreement between the issuing bank and the '
          'cardholder.',
    ),
    // "DEBO Y PAGARE INCONDICIONALMENTE A LA ORDEN DE … LA CANTIDAD DE …".
    (
      RegExp(r'^debo\s+y\s+pagar[eé]\b', caseSensitive: false),
      'I owe and will unconditionally pay, to the order of the payee, the '
          'amount of this promissory note.',
    ),
    // Colombia: "PAGARE INCONDICIONALMENTE Y A LA ORDEN DEL ACREEDOR, EL
    // VALOR TOTAL DE ESTE PAGARE JUNTO CON LOS INTERESES …".
    (
      RegExp(r'^pagar[eé]\s+incondicionalmente\b', caseSensitive: false),
      'I will unconditionally pay, to the order of the creditor, the total '
          'value of this promissory note, with interest at the rates the law '
          'allows.',
    ),
    // "ME OBLIGO A PAGAR AL BANCO EMISOR DE ESTA TARJETA EL MONTO DE ESTA
    // NOTA DE CONSUMO", "ACEPTO PAGAR EL TOTAL DE ESTE DOCUMENTO DE ACUERDO
    // AL CONTRATO CON EL EMISOR".
    (
      RegExp(
        r'^(yo\s+)?(me\s+obligo|me\s+comprometo|prometo|acepto)\s+(a\s+)?'
        r'pagar\b',
        caseSensitive: false,
      ),
      'I agree to pay the card issuer the total of this transaction under '
          'the cardholder agreement.',
    ),
    (
      RegExp(
        r'^(el\s+)?tarjeta\s?habiente\s+(se\s+obliga|se\s+compromete|acepta)'
        r'\s+(a\s+)?pagar\b',
        caseSensitive: false,
      ),
      'The cardholder agrees to pay the card issuer the total of this '
          'transaction under the cardholder agreement.',
    ),
    (
      RegExp(r'^pagar[eé]\s+negociable\s+[uú]nicamente', caseSensitive: false),
      'Promissory note negotiable only with credit institutions',
    ),
    // Colombia: "ESTA FACTURA SE ASIMILA EN TODOS SUS EFECTOS A UNA LETRA DE
    // CAMBIO (ART. 774 DEL CODIGO DE COMERCIO)".
    (
      RegExp(r'^esta\s+factura\s+(de\s+venta\s+)?se\s+asimila',
          caseSensitive: false),
      'This invoice is treated for all legal purposes as a bill of exchange.',
    ),
    (
      RegExp(r'^autorizado\s+(con|mediante|por)\s+(pin|nip)\b',
          caseSensitive: false),
      'Authorised with PIN',
    ),
    (
      RegExp(r'^autorizado\s+(con|mediante|por)\s+firma\s+electr',
          caseSensitive: false),
      'Authorised by electronic signature',
    ),
    (
      RegExp(r'^autorizado\s+sin\s+firma', caseSensitive: false),
      'Authorised without signature',
    ),
    (
      RegExp(r'^por\s+favor\s+conserve\s+este\s+ticket', caseSensitive: false),
      'Please keep this receipt',
    ),
    (
      RegExp(r'^(operaci[oó]n\s+)?contactless\b', caseSensitive: false),
      'Contactless payment',
    ),
  ];

  /// The papers a notice talks about ("ESTE TICKET NO ES…").
  static const String _paper =
      '(documento|ticket|tiquete|comprobante|recibo|boleto|vale|voucher|nota|'
      'factura)';
  static const Map<String, String> _paperEnglish = {
    'documento': 'document', 'ticket': 'receipt', 'tiquete': 'receipt', //
    'comprobante': 'receipt', 'recibo': 'receipt', 'boleto': 'ticket',
    'vale': 'voucher', 'voucher': 'voucher', 'nota': 'note',
    'factura': 'invoice',
  };

  static (RegExp, String Function(Match)) _notice(
    String pattern,
    String Function(Match) english,
  ) =>
      (RegExp('(?:$pattern)(?= |\$)'), english);

  /// Standard notices: thanks, "not a tax receipt", "keep your receipt",
  /// returns, tax status. Matched against the line in lower case without
  /// accents or punctuation, and only when the notices account for the
  /// whole line ("GRACIAS POR SU COMPRA VUELVA PRONTO" is two of them; a
  /// line that says anything more is left to the model).
  static final List<(RegExp, String Function(Match))> _notices = [
    _notice(
      '(?:muchas )?gracias por su '
          '(compra|preferencia|visita|pago|confianza|eleccion|estancia)',
      (m) => switch (m[1]) {
        'compra' => 'Thank you for your purchase',
        'visita' => 'Thank you for your visit',
        'pago' => 'Thank you for your payment',
        'confianza' => 'Thank you for your trust',
        'estancia' => 'Thank you for your stay',
        _ => 'Thank you for choosing us',
      },
    ),
    _notice(
      'gracias por (viajar|volar|comprar|hospedarse) con nosotros',
      (m) => switch (m[1]) {
        'viajar' => 'Thank you for travelling with us',
        'volar' => 'Thank you for flying with us',
        'hospedarse' => 'Thank you for staying with us',
        _ => 'Thank you for shopping with us',
      },
    ),
    _notice('gracias por (?:elegirnos|preferirnos)',
        (_) => 'Thank you for choosing us'),
    _notice('gracias por visitarnos', (_) => 'Thank you for visiting us'),
    _notice('(?:muchas )?gracias', (_) => 'Thank you'),
    _notice('vuelva pronto', (_) => 'Come back soon'),
    _notice('(?:lo|le|la|los|te) esperamos (?:pronto|de nuevo|nuevamente)',
        (_) => 'We hope to see you again soon'),
    _notice('(?:buen|feliz) viaje', (_) => 'Have a good trip'),
    _notice('(?:que )?tenga (?:un )?(?:buen|excelente|bonito|feliz) viaje',
        (_) => 'Have a good trip'),
    _notice('(?:que )?tenga (?:un )?(?:buen|excelente|bonito|feliz) dia',
        (_) => 'Have a nice day'),
    _notice('fue un placer (?:atenderle|atenderlo|servirle)',
        (_) => 'It was a pleasure to serve you'),
    // Not a tax document.
    _notice(
      '(?:este|esta) $_paper no es (?:un |una )?'
          '(comprobante fiscal|factura)(?: valid[oa])?',
      (m) => 'This ${_paperEnglish[m[1]]} is not '
          '${m[2] == 'factura' ? 'an invoice' : 'a tax receipt'}',
    ),
    _notice('(?:este )?no es (?:un )?comprobante fiscal',
        (_) => 'This is not a tax receipt'),
    _notice(
      '(?:(?:este|esta) $_paper )?no (?:es )?valid[oa] como '
          '(comprobante fiscal|factura)',
      (m) => 'Not valid as ${m[2] == 'factura' ? 'an invoice' : 'a tax receipt'}',
    ),
    _notice(
      '(?:(?:este |esta )?$_paper )?(?:sin|no tiene|carece de) '
          '(?:valor|validez|efectos?) fiscal(?:es)?',
      (_) => 'Not valid for tax purposes',
    ),
    _notice(
      '(?:(?:este|esta) $_paper )?no (?:es )?valid[oa] para '
          '(?:efectos|fines) fiscales',
      (_) => 'Not valid for tax purposes',
    ),
    _notice('(?:documento|comprobante|ticket) no fiscal',
        (_) => 'Non-fiscal document'),
    // Keep your receipt.
    _notice(
      '(?:por favor |favor de )?(?:conserve|conservar|guarde|guardar) '
          '(?:su|este|esta|el|la) $_paper'
          '(?: para (?:cualquier |futuras |posibles )?'
          '(aclaracion|aclaraciones|reclamacion|reclamaciones|reclamo|'
          'reclamos|duda|dudas|cambio o devolucion|cambios o devoluciones|'
          'cambios y devoluciones))?',
      (m) => 'Please keep your ${_paperEnglish[m[1]]}'
          '${m[2] == null ? '' : m[2]!.startsWith('cambio') ? ' for '
              'exchanges or refunds' : ' for any queries'}',
    ),
    // Returns.
    _notice(
      '(?:no se (?:aceptan|admiten|hacen|realizan)|no hay|sin) '
          '(cambios ni devoluciones|devoluciones ni cambios|devoluciones|'
          'cambios|reembolsos)',
      (m) => switch (m[1]) {
        'devoluciones' || 'reembolsos' => 'No refunds',
        'cambios' => 'No exchanges',
        _ => 'No exchanges or refunds',
      },
    ),
    _notice(
      '(?:cambios y devoluciones|cambios o devoluciones|cambios|'
          'devoluciones) (?:solo|solamente|unicamente) con '
          '(?:su |el |este )?ticket(?: de compra)?',
      (_) => 'Exchanges and refunds only with the receipt',
    ),
    // Payment and validity.
    _notice('pago en una sola exhibicion',
        (_) => 'Payment in a single instalment'),
    _notice(
      '(?:este|esta) $_paper no es valid[oa] sin (?:el |la )?(sello|firma)'
          '(?: (?:y|ni) (?:el |la )?(sello|firma))?'
          '(?: (?:del|de la|de) (cajero|cajera|caja|empresa|establecimiento))?',
      (m) {
        String word(String? spanish) =>
            spanish == 'sello' ? 'a stamp' : 'a signature';
        const who = {
          'cajero': ' from the cashier', 'cajera': ' from the cashier', //
          'caja': ' from the till', 'empresa': ' from the company',
          'establecimiento': ' from the establishment',
        };
        return 'This ${_paperEnglish[m[1]]} is not valid without '
            '${word(m[2])}${m[3] == null ? '' : ' and ${word(m[3])}'}'
            '${who[m[4]] ?? ''}';
      },
    ),
    _notice(
      '(?:este |el )?boleto (?:debe|debera) (?:ser )?'
          '(?:presentado|presentarse|entregado|entregarse) '
          '(?:a|en) la salida',
      (_) => 'This ticket must be handed in at the exit',
    ),
    _notice('(?:boleto|pago|tarifa|compra) no reembolsable',
        (_) => 'Non-refundable'),
    _notice(
      '(?:favor de pagar|pague)(?: su boleto)? antes de '
          '(?:salir|retirar su (?:vehiculo|auto)|ir por su (?:vehiculo|auto))',
      (_) => 'Please pay before leaving',
    ),
    _notice('no (?:requiere|se requiere) firma|firma no requerida',
        (_) => 'No signature required'),
    _notice(
      '(?:pin|nip) (?:verificado|validado|correcto|ok)|'
          '(?:verificado|validado) (?:con|por|mediante) (?:pin|nip)',
      (_) => 'PIN verified',
    ),
    _notice('firma electronica', (_) => 'Electronic signature'),
    // Tax status (Guatemala, El Salvador, Venezuela, Mexico).
    _notice('sujeto a pagos trimestrales(?: (?:del |de )?isr)?',
        (_) => 'Subject to quarterly income tax (ISR) payments'),
    _notice('sujeto a retencion definitiva(?: (?:del |de )?isr)?',
        (_) => 'Subject to final income tax (ISR) withholding'),
    _notice('sujeto a pago directo(?: (?:del |de )?isr)?',
        (_) => 'Subject to direct income tax (ISR) payment'),
    _notice('agente (?:retenedor|de retencion) (?:de|del) iva',
        (_) => 'VAT withholding agent'),
    _notice('no (?:genera|da) derecho a credito fiscal',
        (_) => 'Does not give the right to a tax credit'),
    _notice('sin derecho a credito fiscal',
        (_) => 'Without the right to a tax credit'),
    _notice('efectos fiscales al pago', (_) => 'Tax effects on payment'),
    _notice('venta al publico en general',
        (_) => 'Sale to the general public'),
    _notice(
      '(?:este documento es (?:una |la )?)?representacion '
          '(?:impresa|grafica) de (?:un |una |la )?'
          '(?:cfdi|comprobante fiscal digital(?: por internet)?|'
          'factura electronica|documento tributario electronico)',
      (_) => 'Printed copy of an electronic tax invoice',
    ),
    _notice(
      '(?:exija|solicite|pida) su $_paper',
      (m) => 'Ask for your ${_paperEnglish[m[1]]}',
    ),
    _notice(
      '(?:los )?precios? (?:incluyen?|con) (?:el )?iva(?: incluido)?',
      (_) => 'Prices include VAT',
    ),
    _notice('impuestos incluidos', (_) => 'Taxes included'),
    _notice(
      '(?:la )?propina (?:no es obligatoria|es voluntaria|es opcional)',
      (_) => 'Tipping is voluntary',
    ),
    _notice('(?:propina no incluida|no incluye propina)',
        (_) => 'Tip not included'),
    _notice('(?:servicio no incluido|no incluye servicio)',
        (_) => 'Service not included'),
    // Car parks.
    _notice(
      '(?:la empresa |el estacionamiento |la administracion )?'
          'no (?:se hace|nos hacemos) responsables? (?:por|de) '
          '(?:los )?(?:objetos|articulos|valores)(?: de valor)?'
          '(?: (?:olvidados|dejados|abandonados))?'
          '(?: (?:en|dentro de|en el interior de) (?:su|el|los|sus) '
          '(?:vehiculos?|autos?|automovil|automoviles|unidad))?',
      (_) => 'We are not responsible for items left in the vehicle',
    ),
  ];

  /// "GRAC1AS POR SU C0MPRA": digits standing for the letters they look
  /// like, inside a word.
  static String _lettersFor(String key) => key.replaceAllMapped(
        RegExp(r'[a-z]+[0158][a-z0158]*|[0158]+[a-z][a-z0158]*'),
        (m) => m[0]!
            .replaceAll('0', 'o')
            .replaceAll('1', 'i')
            .replaceAll('5', 's')
            .replaceAll('8', 'b'),
      );

  /// The English for a line made up of standard notices and nothing else.
  static String? _noticesIn(String text) {
    final key = _lettersFor(TextNormaliser.glossaryKey(text));
    if (key.isEmpty) return null;
    final english = <String>[];
    var at = 0;
    while (at < key.length) {
      Match? best;
      String Function(Match)? say;
      for (final (pattern, builder) in _notices) {
        final m = pattern.matchAsPrefix(key, at);
        if (m != null && (best == null || m.end > best.end)) {
          best = m;
          say = builder;
        }
      }
      if (best == null) return null;
      english.add(say!(best));
      at = best.end + 1;
    }
    return english.join('. ');
  }

  /// The fixed English for [text], or null.
  static String? translate(String text, String language) {
    if (language != 'es') return null;
    for (final (pattern, english) in _spanish) {
      if (pattern.hasMatch(text.trim())) return english;
    }
    return _noticesIn(text) ?? _amountInWords(text);
  }

  /// The currency an amount in words is in ("… QUETZALES CON 00/100").
  static const List<(String, String)> _currencyWords = [
    ('dol', ' dollars'), ('bol', ' bolívares'), ('quetzal', ' quetzales'), //
    ('lempira', ' lempiras'), ('colon', ' colones'), ('cordoba', ' córdobas'),
    ('reais', ' reais'), ('real', ' reais'), ('euro', ' euros'),
    ('sol', ' soles'), ('pes', ' pesos'), ('m.n', ' pesos'),
  ];

  /// "Trescientos Pesos 00/100 M.N." -> "Three hundred pesos 00/100 M.N."
  /// (the model reads a misprinted "Trasoientos Pesos" as "Surroundings
  /// weights"). Only for a line that is the amount and nothing else: a line
  /// that also carries figures ("TOTAL: 300.00 (TRESCIENTOS PESOS…)") would
  /// lose them.
  static String? _amountInWords(String text) {
    if (!RegExp(r'^\W*[A-Za-zÀ-ÿ]').hasMatch(text)) return null;
    final figures = text.replaceAll(RegExp(r'\b[\dOoQ]{1,2}\s?/\s?[1Il][0Oo]{2}'), '');
    if (RegExp(r'\d').hasMatch(figures)) return null;
    final found = AmountInWords.find([text]);
    if (found.length != 1 || !found.single.formal) return null;
    final amount = found.single;
    if (amount.whole <= 0) return null;
    final lower = TextNormaliser.stripDiacritics(text).toLowerCase();
    var currency = '';
    for (final (spanish, english) in _currencyWords) {
      if (lower.contains(spanish)) {
        currency = english;
        break;
      }
    }
    final cents = amount.cents == null
        ? ''
        : ' ${amount.cents.toString().padLeft(2, '0')}/100';
    final national = RegExp(r'm\.?\s?n\b').hasMatch(lower)
        ? ' (national currency)'
        : '';
    final words = numberInEnglish(amount.whole);
    return '${words[0].toUpperCase()}${words.substring(1)}'
        '$currency$cents$national';
  }

  static const List<String> _units = [
    'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
    'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
    'sixteen', 'seventeen', 'eighteen', 'nineteen',
  ];
  static const List<String> _tens = [
    '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
    'eighty', 'ninety',
  ];

  /// 3760 -> "three thousand seven hundred sixty".
  static String numberInEnglish(int n) {
    if (n < 20) return _units[n];
    if (n < 100) {
      return n % 10 == 0
          ? _tens[n ~/ 10]
          : '${_tens[n ~/ 10]}-${_units[n % 10]}';
    }
    for (final (size, name) in const [
      (1000000000, 'billion'),
      (1000000, 'million'),
      (1000, 'thousand'),
      (100, 'hundred'),
    ]) {
      if (n >= size) {
        final rest = n % size;
        return '${numberInEnglish(n ~/ size)} $name'
            '${rest == 0 ? '' : ' ${numberInEnglish(rest)}'}';
      }
    }
    return '$n';
  }
}


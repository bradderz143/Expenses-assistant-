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

/// Standard wording printed on card slips, with a fixed translation: the
/// on-device model mangles legal text ("For this promise I force myself").
class KnownPhrases {
  KnownPhrases._();

  static final List<(RegExp, String)> _spanish = [
    (
      RegExp(r'^por\s+este\s+pagar[eé]\b', caseSensitive: false),
      'By this promissory note I unconditionally promise to pay to the order '
          'of the issuing bank the amount of this document. This note arises '
          'from the credit agreement between the issuing bank and the '
          'cardholder.',
    ),
    (
      RegExp(r'^autorizado\s+con\s+pin', caseSensitive: false),
      'Authorised with PIN',
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

  /// The fixed English for [text], or null.
  static String? translate(String text, String language) {
    if (language != 'es') return null;
    for (final (pattern, english) in _spanish) {
      if (pattern.hasMatch(text.trim())) return english;
    }
    return _amountInWords(text);
  }

  /// "Trescientos Pesos 00/100 M.N." -> "Three hundred pesos 00/100 M.N."
  /// (the model reads a misprinted "Trasoientos Pesos" as "Surroundings
  /// weights"). Only for a line that is the amount and nothing else.
  static String? _amountInWords(String text) {
    if (!RegExp(r'^\W*[A-Za-zÀ-ÿ]').hasMatch(text)) return null;
    final found = AmountInWords.find([text]);
    if (found.length != 1 || !found.single.formal) return null;
    final amount = found.single;
    if (amount.whole <= 0) return null;
    final lower = TextNormaliser.stripDiacritics(text).toLowerCase();
    final currency = lower.contains('dol')
        ? ' dollars'
        : lower.contains('bol')
            ? ' bolívares'
            : lower.contains('real') || lower.contains('reais')
                ? ' reais'
                : lower.contains('euro')
                    ? ' euros'
                    : lower.contains('pes') || lower.contains('m.n')
                        ? ' pesos'
                        : '';
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


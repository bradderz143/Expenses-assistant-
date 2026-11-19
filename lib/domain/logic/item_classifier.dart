import '../entities/enums.dart';
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
    RegExp(r'\bbot\b', caseSensitive: false): 'botella',
    RegExp(r'\bens\b', caseSensitive: false): 'ensalada',
    RegExp(r'\bcerv\b', caseSensitive: false): 'cerveza',
    RegExp(r'\bhamb\b', caseSensitive: false): 'hamburguesa',
  };

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
    return null;
  }
}


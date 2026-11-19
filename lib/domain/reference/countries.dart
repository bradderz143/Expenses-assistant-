/// Country reference data: default currency and the language receipts are
/// most likely to be printed in (a BCP-47 code understood by ML Kit).
class Country {
  const Country(
    this.name,
    this.isoCode,
    this.currency,
    this.languageCode, {
    this.monthFirstDates = false,
  });

  final String name;
  final String isoCode;
  final String currency;
  final String languageCode;

  /// True where receipts print dates as MM/DD/YYYY.
  final bool monthFirstDates;
}

class Countries {
  Countries._();

  static const String defaultCountry = 'Mexico';

  static const List<Country> all = [
    Country('Mexico', 'MX', 'MXN', 'es'),
    Country('Venezuela', 'VE', 'VES', 'es'),
    Country('United Kingdom', 'GB', 'GBP', 'en'),
    Country('United States', 'US', 'USD', 'en', monthFirstDates: true),
    Country('Canada', 'CA', 'CAD', 'en'),
    Country('Guatemala', 'GT', 'GTQ', 'es'),
    Country('Belize', 'BZ', 'BZD', 'en'),
    Country('Honduras', 'HN', 'HNL', 'es'),
    Country('El Salvador', 'SV', 'USD', 'es'),
    Country('Nicaragua', 'NI', 'NIO', 'es'),
    Country('Costa Rica', 'CR', 'CRC', 'es'),
    Country('Panama', 'PA', 'USD', 'es'),
    Country('Cuba', 'CU', 'CUP', 'es'),
    Country('Dominican Republic', 'DO', 'DOP', 'es'),
    Country('Haiti', 'HT', 'HTG', 'fr'),
    Country('Jamaica', 'JM', 'JMD', 'en'),
    Country('Colombia', 'CO', 'COP', 'es'),
    Country('Ecuador', 'EC', 'USD', 'es'),
    Country('Peru', 'PE', 'PEN', 'es'),
    Country('Bolivia', 'BO', 'BOB', 'es'),
    Country('Chile', 'CL', 'CLP', 'es'),
    Country('Argentina', 'AR', 'ARS', 'es'),
    Country('Uruguay', 'UY', 'UYU', 'es'),
    Country('Paraguay', 'PY', 'PYG', 'es'),
    Country('Brazil', 'BR', 'BRL', 'pt'),
    Country('Spain', 'ES', 'EUR', 'es'),
    Country('Portugal', 'PT', 'EUR', 'pt'),
    Country('France', 'FR', 'EUR', 'fr'),
    Country('Belgium', 'BE', 'EUR', 'fr'),
    Country('Netherlands', 'NL', 'EUR', 'nl'),
    Country('Germany', 'DE', 'EUR', 'de'),
    Country('Austria', 'AT', 'EUR', 'de'),
    Country('Switzerland', 'CH', 'CHF', 'de'),
    Country('Italy', 'IT', 'EUR', 'it'),
    Country('Ireland', 'IE', 'EUR', 'en'),
    Country('Poland', 'PL', 'PLN', 'pl'),
    Country('Czechia', 'CZ', 'CZK', 'cs'),
    Country('Romania', 'RO', 'RON', 'ro'),
    Country('Ukraine', 'UA', 'UAH', 'uk'),
    Country('Turkey', 'TR', 'TRY', 'tr'),
    Country('Ghana', 'GH', 'GHS', 'en'),
    Country('Nigeria', 'NG', 'NGN', 'en'),
    Country('Kenya', 'KE', 'KES', 'en'),
    Country('Ethiopia', 'ET', 'ETB', 'en'),
    Country('South Africa', 'ZA', 'ZAR', 'en'),
    Country('Morocco', 'MA', 'MAD', 'fr'),
    Country('Egypt', 'EG', 'EGP', 'en'),
    Country('Jordan', 'JO', 'JOD', 'en'),
    Country('United Arab Emirates', 'AE', 'AED', 'en'),
    Country('Saudi Arabia', 'SA', 'SAR', 'en'),
    Country('Qatar', 'QA', 'QAR', 'en'),
    Country('India', 'IN', 'INR', 'en'),
    Country('Pakistan', 'PK', 'PKR', 'en'),
    Country('Bangladesh', 'BD', 'BDT', 'en'),
    Country('Sri Lanka', 'LK', 'LKR', 'en'),
    Country('China', 'CN', 'CNY', 'zh'),
    Country('Hong Kong', 'HK', 'HKD', 'en'),
    Country('Japan', 'JP', 'JPY', 'ja'),
    Country('South Korea', 'KR', 'KRW', 'ko'),
    Country('Thailand', 'TH', 'THB', 'th'),
    Country('Vietnam', 'VN', 'VND', 'vi'),
    Country('Indonesia', 'ID', 'IDR', 'id'),
    Country('Malaysia', 'MY', 'MYR', 'ms'),
    Country('Philippines', 'PH', 'PHP', 'en'),
    Country('Singapore', 'SG', 'SGD', 'en'),
    Country('Australia', 'AU', 'AUD', 'en'),
    Country('New Zealand', 'NZ', 'NZD', 'en'),
  ];

  static List<String> get names => [for (final c in all) c.name];

  static Country? byName(String? name) {
    if (name == null) return null;
    final key = name.trim().toLowerCase();
    for (final c in all) {
      if (c.name.toLowerCase() == key) return c;
    }
    return null;
  }

  /// Names that also appear on menus or in everyday text ("chile relleno",
  /// "turkey club", "agua de jamaica"), so they are not trusted on their own.
  static const Set<String> _ambiguousNames = {
    'chile', 'turkey', 'jordan', 'cuba', 'jamaica', 'india', 'panama',
    'china', 'argentina', //
  };

  /// City and local-name hints that identify a country on a receipt header.
  static const Map<String, String> _placeHints = {
    'san salvador': 'El Salvador',
    'cdmx': 'Mexico',
    'ciudad de mexico': 'Mexico',
    'tegucigalpa': 'Honduras',
    'managua': 'Nicaragua',
    'caracas': 'Venezuela',
    'bogota': 'Colombia',
    'quito': 'Ecuador',
    'guayaquil': 'Ecuador',
    'london': 'United Kingdom',
    // Mexico
    'sa de cv': 'Mexico',
    's a de c v': 'Mexico',
    'guadalajara': 'Mexico',
    'monterrey': 'Mexico',
    'cancun': 'Mexico',
    'yucatan': 'Mexico',
    'oaxaca': 'Mexico',
    'puebla': 'Mexico',
    'tijuana': 'Mexico',
    'queretaro': 'Mexico',
    'polanco': 'Mexico',
    'mexicofacturas': 'Mexico',
    // Venezuela
    'seniat': 'Venezuela',
    'chacao': 'Venezuela',
    'maracaibo': 'Venezuela',
    'barquisimeto': 'Venezuela',
    'bolivares': 'Venezuela',
    // Central America
    'antiguo cuscatlan': 'El Salvador',
    'santa tecla': 'El Salvador',
    'san pedro sula': 'Honduras',
    'ciudad de guatemala': 'Guatemala',
    'ciudad de panama': 'Panama',
    'medellin': 'Colombia',
    'cartagena': 'Colombia',
    'santo domingo': 'Dominican Republic',
    'buenos aires': 'Argentina',
    'montevideo': 'Uruguay',
    'santiago de chile': 'Chile',
  };

  static const Map<String, String> _foldMap = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
    'ë': 'e', 'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o',
    'ô': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n',
  };

  /// The country a receipt was issued in, judged from its printed text (a
  /// country name or a well-known city). Null when nothing clear is found.
  static String? detectInText(String text) {
    var haystack = text.toLowerCase();
    _foldMap.forEach((from, to) => haystack = haystack.replaceAll(from, to));
    haystack = haystack.replaceAll('new mexico', ' ');
    final scores = <String, int>{};
    void count(String needle, String country) {
      final pattern = RegExp('(?<![a-z])${RegExp.escape(needle)}(?![a-z])');
      final hits = pattern.allMatches(haystack).length;
      if (hits > 0) scores[country] = (scores[country] ?? 0) + hits;
    }

    for (final c in all) {
      final name = c.name.toLowerCase();
      if (!_ambiguousNames.contains(name)) count(name, c.name);
    }
    _placeHints.forEach(count);
    if (scores.isEmpty) return null;
    return scores.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// The country a currency belongs to when only one country in the list
  /// uses it (VES -> Venezuela). Null for shared currencies such as USD
  /// (El Salvador, Ecuador, Panama, US) or EUR: those need other clues.
  static String? fromCurrency(String? code) {
    if (code == null) return null;
    final matches = [
      for (final c in all)
        if (c.currency == code.toUpperCase()) c.name,
    ];
    return matches.length == 1 ? matches.single : null;
  }

  static String currencyFor(String? countryName, {String fallback = 'USD'}) =>
      byName(countryName)?.currency ?? fallback;

  static String? languageFor(String? countryName) =>
      byName(countryName)?.languageCode;

  static bool usesMonthFirstDates(String? countryName) =>
      byName(countryName)?.monthFirstDates ?? false;
}

/// English display names for the language codes the app deals with.
class Languages {
  Languages._();

  static const Map<String, String> _names = {
    'en': 'English',
    'es': 'Spanish',
    'pt': 'Portuguese',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'nl': 'Dutch',
    'pl': 'Polish',
    'cs': 'Czech',
    'ro': 'Romanian',
    'uk': 'Ukrainian',
    'ru': 'Russian',
    'tr': 'Turkish',
    'ar': 'Arabic',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'th': 'Thai',
    'vi': 'Vietnamese',
    'id': 'Indonesian',
    'ms': 'Malay',
    'tl': 'Tagalog',
    'hi': 'Hindi',
    'ur': 'Urdu',
    'bn': 'Bengali',
    'sw': 'Swahili',
  };

  static String nameOf(String? code) {
    if (code == null) return 'Unknown';
    return _names[code] ?? code.toUpperCase();
  }

  /// Closely related languages that on-device identification often mixes up
  /// on short receipt text (Spanish read as Galician, and so on).
  static const Map<String, Set<String>> _confusable = {
    'es': {'gl', 'ca', 'pt', 'an', 'ast', 'oc', 'la', 'eo'},
    'pt': {'gl', 'es', 'ca'},
    'it': {'la', 'co', 'sc'},
    'fr': {'oc', 'br', 'co'},
  };

  /// If [detected] is a language that is easily confused with the
  /// [expected] one (from the country), prefer [expected].
  static String? reconcile(String? detected, String? expected) {
    if (detected == null) return expected;
    if (expected == null || detected == expected) return detected;
    final confusedWith = _confusable[expected];
    if (confusedWith != null && confusedWith.contains(detected)) {
      return expected;
    }
    return detected;
  }

  /// Languages offered in Settings for pre-downloading translation models.
  static List<String> get downloadable =>
      _names.keys.where((code) => code != 'en').toList();
}

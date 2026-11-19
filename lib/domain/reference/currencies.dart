/// ISO 4217 reference data needed for parsing and formatting amounts.
class Currencies {
  Currencies._();

  static const Set<String> zeroDecimal = {
    'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', //
    'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
  };

  static const Set<String> threeDecimal = {
    'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND',
  };

  /// Currencies offered first in pickers. Others can still be typed.
  static const List<String> common = [
    'MXN', 'USD', 'GBP', 'EUR', 'VES', 'COP', 'GTQ', 'PEN', 'CLP', 'ARS', //
    'BRL', 'CRC', 'HNL', 'NIO', 'DOP', 'BOB', 'UYU', 'PYG', 'PAB', 'CUP',
    'CAD', 'CHF', 'NOK', 'SEK', 'DKK', 'PLN', 'CZK', 'HUF', 'RON', 'TRY',
    'UAH', 'GHS', 'NGN', 'KES', 'ZAR', 'ETB', 'EGP', 'MAD', 'AED', 'SAR',
    'QAR', 'KWD', 'BHD', 'OMR', 'JOD', 'INR', 'PKR', 'BDT', 'LKR', 'NPR',
    'CNY', 'HKD', 'JPY', 'KRW', 'THB', 'VND', 'IDR', 'PHP', 'SGD', 'MYR',
    'AUD', 'NZD',
  ];

  /// Symbols that identify a single currency without ambiguity. A bare `$`
  /// is deliberately absent: it is resolved from the country instead.
  static const Map<String, String> unambiguousSymbols = {
    '£': 'GBP',
    '€': 'EUR',
    '₹': 'INR',
    r'R$': 'BRL',
    r'US$': 'USD',
    r'U$S': 'USD',
    'S/': 'PEN',
    '₦': 'NGN',
    '₴': 'UAH',
    '₺': 'TRY',
    '₱': 'PHP',
    '฿': 'THB',
    '₩': 'KRW',
    '₫': 'VND',
    '₵': 'GHS',
    'zł': 'PLN',
  };

  static int exponentOf(String currency) {
    final code = currency.toUpperCase();
    if (zeroDecimal.contains(code)) return 0;
    if (threeDecimal.contains(code)) return 3;
    return 2;
  }

  static bool isValidCode(String code) => RegExp(r'^[A-Z]{3}$').hasMatch(code);
}

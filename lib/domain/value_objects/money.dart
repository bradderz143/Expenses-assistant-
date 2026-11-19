import '../reference/currencies.dart';

/// An amount held in integer minor units (pence, centavos…) so that sums and
/// comparisons never suffer floating-point drift.
class Money {
  const Money(this.minorUnits, this.currency);

  final int minorUnits;
  final String currency;

  int get exponent => Currencies.exponentOf(currency);

  /// Plain decimal, no grouping or symbol: `428.50`. This is the form Oracle
  /// and the package folder name expect.
  String get amountText => formatMinor(minorUnits, exponent);

  @override
  String toString() => '$amountText $currency';

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  static String formatMinor(int minor, int exponent) {
    final sign = minor < 0 ? '-' : '';
    final abs = minor.abs();
    if (exponent == 0) return '$sign$abs';
    final factor = _pow10(exponent);
    final whole = abs ~/ factor;
    final fraction = (abs % factor).toString().padLeft(exponent, '0');
    return '$sign$whole.$fraction';
  }

  /// Parses amounts as typed by a user or read by OCR:
  /// `428.50`, `428,50`, `$1,234.50`, `1.234,50`, `MXN 90`, `(12.00)`.
  ///
  /// Returns null when no number can be found.
  static int? parseMinor(String input, {int exponent = 2}) {
    var text = input.trim();
    if (text.isEmpty) return null;
    final negative = text.startsWith('-') ||
        text.endsWith('-') ||
        (text.startsWith('(') && text.endsWith(')'));
    text = text.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (!RegExp(r'\d').hasMatch(text)) return null;

    final lastDot = text.lastIndexOf('.');
    final lastComma = text.lastIndexOf(',');
    var integerPart = text;
    var fractionPart = '';

    if (lastDot >= 0 && lastComma >= 0) {
      // Both present: whichever comes last is the decimal separator.
      final decimalAt = lastDot > lastComma ? lastDot : lastComma;
      integerPart = text.substring(0, decimalAt).replaceAll(RegExp('[.,]'), '');
      fractionPart = text.substring(decimalAt + 1);
    } else if (lastDot >= 0 || lastComma >= 0) {
      final separator = lastDot >= 0 ? '.' : ',';
      final parts = text.split(separator);
      final groupsOfThree = parts.skip(1).every((p) => p.length == 3);
      final looksLikeThousands =
          groupsOfThree && (parts.length > 2 || exponent != 3);
      if (looksLikeThousands) {
        integerPart = parts.join();
      } else {
        integerPart = parts.sublist(0, parts.length - 1).join();
        fractionPart = parts.last;
      }
    }

    if (integerPart.isEmpty) integerPart = '0';
    if (integerPart.length > 13) return null; // Not a plausible receipt amount.

    final factor = _pow10(exponent);
    var value = int.parse(integerPart) * factor;
    if (exponent > 0 && fractionPart.isNotEmpty) {
      final padded = fractionPart.padRight(exponent, '0');
      value += int.parse(padded.substring(0, exponent));
    }
    if (fractionPart.length > exponent &&
        int.parse(fractionPart[exponent]) >= 5) {
      value += 1; // Round half up.
    }
    return negative ? -value : value;
  }

  static Money? tryParse(String input, String currency) {
    final minor = parseMinor(input, exponent: Currencies.exponentOf(currency));
    return minor == null ? null : Money(minor, currency);
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }
}

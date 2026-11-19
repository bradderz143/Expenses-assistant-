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

/// Turns OCR rows from the item crop into item lines, dropping anything that
/// must not be translated (totals, tax, tips, payment and card details).
class ItemLineParser {
  ItemLineParser._();

  // Whole words (\b) so items such as "Cashews" or "Taxi" are not dropped;
  // a few are prefixes on purpose (autoriz-ación, aprobad-o).
  static final RegExp _skip = RegExp(
    r'^\W*(?:(?:sub\s*-?\s*total|total|iva|i\.v\.a|ieps|vat|tax|impuesto|'
    r'propina|tip|gratuity|service\s*charge|cambio|change|efectivo|cash|'
    r'tarjeta|card|visa|master\s*card|mastercard|amex|american\s*express|'
    r'd[eé]bito|cr[eé]dito|redondeo|rounding|saldo|balance|folio|mesa|table|'
    r'mesero|waiter|comensales|personas|guests|fecha|date|hora|time|rfc|'
    r'r\.f\.c|ticket|gracias|thank|cuenta|importe|amount|pago|payment)\b|'
    r'servicio\s*\d|autoriz|aprobad|approved|auth)',
    caseSensitive: false,
  );

  static final RegExp _trailingAmounts = RegExp(
    r'((?:\s+[$£€]?\s?-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}-?)+)\s*$',
  );

  static final RegExp _amount = RegExp(r'-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}-?');

  static final RegExp _leadingQuantity = RegExp(
    r'^(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:x|X|\*|pz[as]?|pza|pzas|uds?|un)?\.?\s+(?=\D)',
  );

  // ------------------------------------------------- whole-block extraction

  // "12.35", "12.35E" (tax flag), "12.35=", "$12.35".
  static final RegExp _amountToken = RegExp(
    r'^[$£€]?-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}-?=?[A-Za-z]?$',
  );
  static final RegExp _numberToken = RegExp(r'^[$£€]?-?\d+(?:[.,]\d+)?=?$');
  static final RegExp _timesToken = RegExp(r'^[xX×*]$');
  static final RegExp _amountInside =
      RegExp(r'-?(?:\d{1,3}(?:[.,]\d{3})+|\d+)[.,]\d{2}');

  /// Splits "PARIS WARM BOWL 1.00 x 12.35= 12.35E" into the wording and its
  /// trailing quantity / price tokens.
  static (String, List<String>) _splitTail(String text) {
    final tokens = text.split(' ').where((t) => t.isNotEmpty).toList();
    var i = tokens.length;
    while (i > 0 &&
        (_amountToken.hasMatch(tokens[i - 1]) ||
            _timesToken.hasMatch(tokens[i - 1]))) {
      i--;
    }
    // A whole-number quantity directly before an "x": "2 x 55.00 110.00".
    if (i > 0 &&
        i < tokens.length &&
        _timesToken.hasMatch(tokens[i]) &&
        _numberToken.hasMatch(tokens[i - 1])) {
      i--;
    }
    return (tokens.take(i).join(' '), tokens.skip(i).toList());
  }

  static String? _lastAmount(List<String> tail) {
    for (final token in tail.reversed) {
      if (_amountToken.hasMatch(token)) {
        return _amountInside.firstMatch(token)?.group(0);
      }
    }
    return null;
  }

  static String? _quantityOf(List<String> tail) {
    final x = tail.indexWhere(_timesToken.hasMatch);
    if (x <= 0) return null;
    final raw = tail.first.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (raw.isEmpty) return null;
    return raw.replaceAll(RegExp(r'[.,]0+$'), '');
  }

  static String _tidy(String text) {
    var t = text.replaceAll(RegExp(r'^[\s\-*.·:]+|[\s\-*.·:$]+$'), '').trim();
    final qty = _leadingQuantity.firstMatch(t);
    if (qty != null) t = t.substring(qty.end).trim();
    return t;
  }

  static bool _looksLikeName(String head) =>
      !head.contains(':') &&
      TextNormaliser.letterCount(head) >= 3 &&
      RegExp(r'\d').allMatches(head).length <=
          TextNormaliser.letterCount(head);

  /// True for the totals block under the items (subtotal, tip, total) and
  /// for rows holding only numbers.
  static bool isSummaryRow(String row) {
    final text = TextNormaliser.collapseSpaces(row);
    if (text.isEmpty) return false;
    if (_skip.hasMatch(text)) return true;
    final (head, tail) = _splitTail(text);
    return head.isEmpty && tail.isNotEmpty;
  }

  /// Finds the purchased items in OCR rows of a whole receipt or a crop:
  /// everything above the first priced line (address, customer, table, date)
  /// and everything from the subtotal down is ignored. Handles prices on the
  /// same row as the name and the two-row layout where the name sits above
  /// "1.00 x 2.21= 2.21E". Returns an empty list if no priced lines exist.
  /// A date or a time that OCR joined onto an item row from beside it
  /// ("15 NOV 2026  13:44:23  1 VACUNA").
  static final RegExp _dateOrTime = RegExp(
    r'\b\d{1,2}[\s/.\-]+(?:[A-Za-z]{3,10}\.?|\d{1,2})[\s/.\-]+\d{2,4}\b|'
    r'\b\d{1,2}:\d{2}(?::\d{2})?(?:\s?[AaPp]\.?[Mm]\.?)?',
  );

  /// "Bs.S5.445,32", "Bs S10. 164,60", "MX$90.00": a currency written in
  /// front of a price, and a number OCR split at its separator.
  static final RegExp _currencyPrefix = RegExp(
    r'(?<![A-Za-z])(?:Bs\.?\s?S?\.?|MX\$|US\$|S/\.?|Q\.?)\s?(?=[0-9IlO])',
  );
  static final RegExp _splitNumber = RegExp(r'(\d)([.,])\s(\d{3}[.,]\d{2})\b');

  static String _withoutDates(String row) => TextNormaliser.collapseSpaces(row
      .replaceAll(_dateOrTime, ' ')
      .replaceAll(_currencyPrefix, '')
      .replaceAllMapped(_splitNumber, (m) => '${m[1]}${m[2]}${m[3]}'));

  static List<ReceiptItem> extract(List<String> rows) {
    final items = <ReceiptItem>[];
    var started = false;
    var i = 0;
    while (i < rows.length) {
      final text = _withoutDates(rows[i]);
      if (text.isEmpty) {
        i++;
        continue;
      }
      if (_skip.hasMatch(text)) {
        if (started) break;
        i++;
        continue;
      }
      final (head, tail) = _splitTail(text);
      final name = _tidy(head);

      if (TextNormaliser.letterCount(name) >= 2 &&
          tail.any(_amountToken.hasMatch)) {
        started = true;
        items.add(ReceiptItem(
          description: name,
          quantity: _quantityOf(tail) ?? _leadingQuantity.firstMatch(head)?.group(1),
          amountText: _lastAmount(tail),
          firstRow: i,
          lastRow: i,
        ));
        i++;
        continue;
      }

      if (!tail.any(_amountToken.hasMatch) && _looksLikeName(head)) {
        final numbers = <String>[...tail];
        var j = i + 1;
        var last = i;
        var seen = 0;
        while (j < rows.length && seen < 2) {
          final next = _withoutDates(rows[j]);
          if (next.isEmpty) {
            j++;
            continue;
          }
          final (nextHead, nextTail) = _splitTail(next);
          if (nextHead.isNotEmpty || nextTail.isEmpty) break;
          numbers.addAll(nextTail);
          last = j;
          seen++;
          j++;
        }
        if (seen > 0 && numbers.any(_amountToken.hasMatch)) {
          started = true;
          items.add(ReceiptItem(
            description: name,
            // A unit price read on the name row is not a quantity.
            quantity: tail.isEmpty ? _quantityOf(numbers) : null,
            amountText: _lastAmount(numbers),
            firstRow: i,
            lastRow: last,
          ));
          i = last + 1;
          continue;
        }
      }
      i++;
    }
    return items;
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
    if (_skip.hasMatch(text)) return null;

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

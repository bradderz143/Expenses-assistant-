import 'dart:io';

import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'corpus/ordinary_receipts.dart';

/// A change detector for the receipt readers.
///
/// test/corpus/readings.txt records what the readers return today for every
/// receipt in the corpus: shop, date, amount and currency, then the items as
/// "quantity|name|amount". Some of those readings are known to be wrong; the
/// file is not a list of right answers. It exists so that a change to the
/// rules shows every ordinary receipt it touches: when this test fails, look
/// at each difference it prints, and if all are meant, record them with
///
///   UPDATE_READINGS=1 flutter test test/corpus_snapshot_test.dart
String _readings() {
  final out = StringBuffer();
  for (var n = 0; n < ordinaryReceipts.length; n++) {
    final (name, rows) = ordinaryReceipts[n];
    final parsed = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 23, 9),
    ).parseRows(rows);
    final date = parsed.date?.toIso8601String().substring(0, 10);
    out.writeln('=== ${n + 1} $name');
    out.writeln('  ${parsed.merchant} | $date | ${parsed.amountMinor} '
        '${parsed.currency}');
    for (final item in ItemLineParser.extract(rows)) {
      out.writeln('  ${item.quantity ?? ''}|${item.description}|'
          '${item.amountText ?? ''}');
    }
  }
  return out.toString();
}

Map<String, List<String>> _byReceipt(String text) {
  final receipts = <String, List<String>>{};
  var name = '';
  for (final line in text.split('\n')) {
    if (line.startsWith('=== ')) {
      name = line.substring(4);
      receipts[name] = [];
    } else if (line.trim().isNotEmpty) {
      receipts[name]?.add(line.trim());
    }
  }
  return receipts;
}

void main() {
  test('ordinary receipts read as recorded', () {
    final file = File('test/corpus/readings.txt');
    final now = _readings();
    if (Platform.environment['UPDATE_READINGS'] == '1' || !file.existsSync()) {
      file.writeAsStringSync(now);
      return;
    }
    final before = _byReceipt(file.readAsStringSync());
    final after = _byReceipt(now);
    final changes = <String>[];
    for (final name in {...before.keys, ...after.keys}) {
      final was = before[name] ?? const <String>[];
      final becomes = after[name] ?? const <String>[];
      if (was.join('\n') == becomes.join('\n')) continue;
      changes.add('$name\n'
          '    was: ${was.where((l) => !becomes.contains(l)).join(' ; ')}\n'
          '    now: ${becomes.where((l) => !was.contains(l)).join(' ; ')}');
    }
    expect(
      changes,
      isEmpty,
      reason: '${changes.length} receipt(s) read differently from '
          'test/corpus/readings.txt:\n${changes.join('\n')}\n'
          'If every change is meant, record it: '
          'UPDATE_READINGS=1 flutter test test/corpus_snapshot_test.dart',
    );
  });
}

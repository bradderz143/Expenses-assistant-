// Scratch probe: prints the notes for real receipt texts. Not committed.
import 'dart:convert';
import 'dart:io';

import 'package:expense_assistant/domain/logic/receipt_notes.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bakery_ticket_test.dart' as bakery;
import 'card_slip_text_test.dart' as cs;
import 'fast_food_ticket_test.dart' as ff;
import 'receipt_notes_test.dart' as rn;
import 'scan_misread_test.dart' as sm;

void dump(String name, List<String> rows) {
  final b = StringBuffer('== $name\n');
  for (final n in ReceiptNotes.find(rows)) {
    b.writeln('  [${n.kind.name}] ${n.title}');
    if (n.detail != null) {
      b.writeln('      detail: ${n.detail!.replaceAll('\n', ' | ')}');
    }
    if (n.printed != null) b.writeln('      printed: ${n.printed}');
  }
  // ignore: avoid_print
  print(b);
}

void main() {
  test('dump', () {
    final src = File('test/review_cases_test.dart').readAsStringSync();
    for (final name in ['_cafeText', '_xetuxText', '_coffeeText']) {
      final m = RegExp("const $name = '''(.*?)''';", dotAll: true)
          .firstMatch(src)!;
      dump(name, m[1]!.replaceAll(r'\$', r'$').split('\n'));
    }
    dump('bakery', bakery.ticket);
    dump('coffee', rn.coffee);
    dump('fastFood', rn.fastFood);
    dump('slip', cs.slip);
    dump('kfc', ff.ticket);
    dump('bill', sm.sampleBillRows);
    final data = jsonDecode(
      File('test/fixtures/bill_misreads.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final f
        in (data['fixtures'] as List).cast<Map<String, dynamic>>().take(8)) {
      dump(f['id'] as String, (f['rows'] as List).cast<String>());
    }
    final extra = File('test/zz_probe_extra.txt');
    if (extra.existsSync()) {
      for (final part in extra.readAsStringSync().split('\n#')) {
        final rows = part.split('\n');
        dump(rows.first, rows.skip(1).where((r) => r.isNotEmpty).toList());
      }
    }
  });
}

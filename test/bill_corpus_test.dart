import 'dart:convert';
import 'dart:io';

import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Many plausible OCR misreads of one real receipt (a restaurant bill, Mexico
/// City, 28/07/2026, 3,760.00 pesos), each with the truth of the paper and
/// whether the rows alone are enough to recover it.
///
/// The rule for every one: when the rows settle the amount (or the date) the
/// parser must return it; when they do not, it must return nothing or flag
/// what it returns. It must never be confidently wrong.
void main() {
  final data = jsonDecode(
    File('test/fixtures/bill_misreads.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final fixtures =
      (data['fixtures'] as List<dynamic>).cast<Map<String, dynamic>>();

  for (final f in fixtures) {
    test('${f['lens']}: ${f['id']}', () {
      final today = DateTime.parse(f['today'] as String);
      final parsed = ReceiptTextParser(
        defaultCurrency: f['defaultCurrency'] as String,
        monthFirstDates: f['monthFirstDates'] as bool,
        clock: () => DateTime(today.year, today.month, today.day, 18),
      ).parseRows((f['rows'] as List<dynamic>).cast<String>());
      final scenario = f['scenario'] as String;

      final amount = f['trueAmountMinor'] as int;
      if (f['amountRecoverable'] as bool) {
        expect(parsed.amountMinor, amount, reason: scenario);
      } else {
        expect(
          parsed.amountMinor == null || parsed.amountDoubtful,
          isTrue,
          reason: 'confidently read ${parsed.amountMinor}: $scenario',
        );
      }

      final date = DateTime.parse(f['trueDate'] as String);
      if (f['dateRecoverable'] as bool) {
        expect(parsed.date, date, reason: scenario);
      } else {
        expect(
          parsed.date == null || parsed.dateDoubtful,
          isTrue,
          reason: 'confidently read ${parsed.date}: $scenario',
        );
      }
    });
  }
}

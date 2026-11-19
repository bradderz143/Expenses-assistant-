import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/presentation/common/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('status chips show workflow labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (final s in ReceiptStatus.values) StatusChip(s),
          ],
        ),
      ),
    ));
    expect(find.text('Needs details'), findsOneWidget);
    expect(find.text('Needs translation'), findsOneWidget);
    expect(find.text('Ready to submit'), findsOneWidget);
    expect(find.text('Submitted'), findsOneWidget);
  });

  testWidgets('suggestion chips filter by what has been typed', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SuggestionChips(
          suggestions: const [
            'Lunch whilst attending ACS workshop',
            'Taxi to embassy',
          ],
          current: 'lunch',
          onSelected: (s) => picked = s,
        ),
      ),
    ));
    expect(find.text('Taxi to embassy'), findsNothing);
    await tester.tap(find.text('Lunch whilst attending ACS workshop'));
    expect(picked, 'Lunch whilst attending ACS workshop');
  });
}

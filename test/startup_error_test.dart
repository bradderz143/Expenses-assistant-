import 'package:expense_assistant/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a failed start shows the error and can be retried',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(StartupErrorApp(
      step: 'opening the database',
      error: Exception('database is locked'),
      stack: StackTrace.current,
      onRetry: () async => retried++,
    ));
    expect(find.text('Expense Assistant could not start'), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });
}

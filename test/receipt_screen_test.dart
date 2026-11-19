import 'dart:io';

import 'package:expense_assistant/application/commands.dart';
import 'package:expense_assistant/data/services/file_storage_service.dart';
import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/entities/receipt.dart';
import 'package:expense_assistant/domain/entities/trip.dart';
import 'package:expense_assistant/domain/repositories/repositories.dart';
import 'package:expense_assistant/presentation/common/widgets.dart';
import 'package:expense_assistant/presentation/providers.dart';
import 'package:expense_assistant/presentation/receipts/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReceipts implements ReceiptRepository {
  FakeReceipts(Receipt receipt) : stored = receipt;

  Receipt stored;

  @override
  Future<Receipt?> getById(String id) async => id == stored.id ? stored : null;

  @override
  Future<void> upsert(Receipt receipt) async => stored = receipt;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTrips implements TripRepository {
  @override
  Future<List<Trip>> getAll() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCommands implements ReceiptCommands {
  FakeCommands(this.repository);

  final FakeReceipts repository;
  final List<Receipt> saved = [];

  @override
  Future<Receipt> saveDetails(Receipt edited) async {
    saved.add(edited);
    await repository.upsert(edited);
    return edited;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Receipt scanned(
  List<ScanCheck> toCheck, {
  int? amountMinor = 376000,
  DateTime? date,
}) =>
    Receipt(
      id: 'r1',
      merchant: 'Restaurante Ejemplo Centro',
      transactionDate: date ?? DateTime(2026, 11, 13),
      amountMinor: amountMinor,
      currency: 'MXN',
      country: 'Mexico',
      claimType: ClaimType.expense,
      translationStatus: TranslationStatus.pending,
      originalImagePath: 'Standalone_Expenses/x/original_receipt.jpg',
      capturedAt: DateTime(2026, 11, 13, 22, 52),
      updatedAt: DateTime(2026, 11, 13, 22, 52),
      toCheck: toCheck,
    );

const dateNotRead =
    'Not read from the receipt. This is the day you scanned it, so please check';
const hardToRead = 'Hard to read. Please check';

void main() {
  /// Opens the review screen for [receipt] from a blank home page.
  Future<FakeCommands> open(
    WidgetTester tester,
    Receipt receipt, {
    String? readNote,
  }) async {
    final repository = FakeReceipts(receipt);
    final commands = FakeCommands(repository);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        receiptRepositoryProvider.overrideWithValue(repository),
        tripRepositoryProvider.overrideWithValue(FakeTrips()),
        receiptCommandsProvider.overrideWithValue(commands),
        fileStorageProvider
            .overrideWithValue(FileStorageService(Directory('/nowhere'))),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    ReceiptScreen(receiptId: receipt.id, readNote: readNote),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return commands;
  }

  testWidgets('shows what the scan was unsure of, and Save settles it',
      (tester) async {
    final commands = await open(
      tester,
      scanned(const [ScanCheck.dateNotRead, ScanCheck.amountUnsure]),
      readNote: 'This photo was hard to read.',
    );
    expect(find.text('This photo was hard to read.'), findsOneWidget);
    expect(find.text(dateNotRead), findsOneWidget);
    expect(find.text(hardToRead), findsOneWidget);
    expect(find.text('13 Nov 2026'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(commands.saved.single.toCheck, isEmpty);
    expect(find.text('open'), findsOneWidget); // back where we came from
  });

  testWidgets('correcting the amount clears its warning only', (tester) async {
    await open(
      tester,
      scanned(const [ScanCheck.dateUnsure, ScanCheck.amountUnsure]),
    );
    expect(find.text(hardToRead), findsNWidgets(2)); // date and amount

    await tester.enterText(find.byType(TextField).first, '3700.00');
    await tester.pumpAndSettle(); // the warning fades out
    expect(find.text(hardToRead), findsOneWidget); // the date still
  });

  testWidgets('an unread amount asks to be typed in', (tester) async {
    await open(
      tester,
      scanned(const [ScanCheck.amountNotRead], amountMinor: null),
    );
    expect(find.text('Not read. Please enter it'), findsOneWidget);
    expect(find.text(hardToRead), findsNothing);
  });

  testWidgets('a receipt read cleanly shows no warnings', (tester) async {
    await open(tester, scanned(const []));
    expect(find.text(dateNotRead), findsNothing);
    expect(find.text(hardToRead), findsNothing);
  });

  testWidgets('the receipt list says what still needs a check', (tester) async {
    Future<void> show(List<ScanCheck> toCheck) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ReceiptTile(
              receipt: scanned(toCheck),
              imagePath: '/nowhere/original_receipt.jpg',
              onTap: () {},
            ),
          ),
        ));
    await show(const [ScanCheck.dateNotRead, ScanCheck.amountUnsure]);
    expect(find.textContaining('Check date and amount'), findsOneWidget);
    await show(const [ScanCheck.dateUnsure]);
    expect(find.textContaining('Check date'), findsOneWidget);
    await show(const [ScanCheck.amountNotRead]);
    expect(find.textContaining('Check amount'), findsOneWidget);
    await show(const []);
    expect(find.textContaining('Check'), findsNothing);
  });

  testWidgets('a flagged date from years ago can still be picked',
      (tester) async {
    await open(
      tester,
      scanned(const [ScanCheck.dateUnsure], date: DateTime(2012, 5, 5)),
    );
    await tester.tap(find.text('05 May 2012'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('the check label fits a narrow phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.5),
        ),
        child: Scaffold(
          body: ReceiptTile(
            receipt: scanned(const [ScanCheck.dateNotRead, ScanCheck.amountUnsure]),
            imagePath: '/nowhere/original_receipt.jpg',
            onTap: () {},
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Check date and amount'), findsOneWidget);
  });

  testWidgets('shows the scanned text on request', (tester) async {
    await open(tester, scanned(const []).copyWith(rawOcrText: 'CAFE EJEMPLO\nTOTAL 31.42'));
    await tester.scrollUntilVisible(find.text('Show scanned text'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Show scanned text'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TOTAL 31.42'), findsOneWidget);
  });
}

import 'dart:io';

import 'package:expense_assistant/application/commands.dart';
import 'package:expense_assistant/data/services/file_storage_service.dart';
import 'package:expense_assistant/domain/entities/receipt.dart';
import 'package:expense_assistant/domain/entities/trip.dart';
import 'package:expense_assistant/presentation/providers.dart';
import 'package:expense_assistant/presentation/trips/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'receipt_screen_test.dart' show scanned;

class FakeTripCommands implements TripCommands {
  FakeTripCommands(this.loose);

  final List<Receipt> loose;
  List<Receipt>? assigned;

  @override
  Future<List<Receipt>> looseReceipts() async => loose;

  @override
  Future<void> assignReceipts(Trip trip, List<Receipt> toAssign) async =>
      assigned = toAssign;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('receipts from the trip dates start ticked; Add files them',
      (tester) async {
    Receipt r(String id, String merchant, DateTime date) =>
        scanned(const [], date: date).copyWith(merchant: merchant).withId(id);
    final inTrip = r('a', 'El Fogon', DateTime(2026, 11, 4));
    final before = r('b', 'the restaurant bill', DateTime(2026, 7, 28));
    final commands = FakeTripCommands([before, inTrip]);
    final trip = Trip(
      id: 't',
      name: 'Workshop',
      country: 'Venezuela',
      folderName: 'Workshop_2026',
      startDate: DateTime(2026, 11, 2),
      endDate: DateTime(2026, 11, 6),
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tripCommandsProvider.overrideWithValue(commands),
        fileStorageProvider
            .overrideWithValue(FileStorageService(Directory('/nowhere'))),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AddReceiptsScreen(trip: trip),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Add 1 receipt'), findsOneWidget);

    // Tick the July one too.
    await tester.tap(find.text('the restaurant bill'));
    await tester.pump();
    expect(find.text('Add 2 receipts'), findsOneWidget);
    await tester.tap(find.text('Add 2 receipts'));
    await tester.pumpAndSettle();
    expect(commands.assigned!.map((r) => r.id).toSet(), {'a', 'b'});
    expect(find.text('open'), findsOneWidget); // back on the trip
  });
}

extension on Receipt {
  Receipt withId(String id) => Receipt(
        id: id,
        merchant: merchant,
        transactionDate: transactionDate,
        amountMinor: amountMinor,
        currency: currency,
        country: country,
        claimType: claimType,
        translationStatus: translationStatus,
        originalImagePath: originalImagePath,
        capturedAt: capturedAt,
        updatedAt: updatedAt,
      );
}

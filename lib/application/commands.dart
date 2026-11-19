import '../data/services/file_storage_service.dart';
import '../domain/entities/app_settings.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/receipt_query.dart';
import '../domain/entities/trip.dart';
import '../domain/logic/merchant_memory.dart';
import '../domain/logic/package_naming.dart';
import '../domain/repositories/repositories.dart';
import 'package_service.dart';

/// Edits to receipts. Every change rewrites the package so the files on disk
/// always match the database.
class ReceiptCommands {
  ReceiptCommands({
    required this.receipts,
    required this.packages,
    required this.packageService,
    required this.storage,
    this.merchantMemory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReceiptRepository receipts;
  final PackageRepository packages;
  final PackageService packageService;
  final FileStorageService storage;

  /// When set, merchant corrections are remembered for next time.
  final MerchantMemoryRepository? merchantMemory;
  final DateTime Function() _clock;

  Future<Receipt> saveDetails(Receipt edited) async {
    final before = await receipts.getById(edited.id);
    final name = edited.merchant?.trim() ?? '';
    if (merchantMemory != null &&
        before != null &&
        name.isNotEmpty &&
        name != (before.merchant?.trim() ?? '') &&
        edited.rawOcrText.trim().isNotEmpty) {
      try {
        await merchantMemory!.remember(MerchantMemory.learn(
          ocrText: edited.rawOcrText,
          merchant: name,
          wrongGuess: before.merchant,
        ));
      } on Object {
        // Learning is a nicety; never block saving the receipt.
      }
    }
    await receipts.upsert(edited.copyWith(updatedAt: _clock()));
    await packageService.rebuild(edited.id);
    return (await receipts.getById(edited.id))!;
  }

  Future<void> setSubmitted(Receipt receipt, {required bool submitted}) async {
    await receipts.upsert(receipt.copyWith(
      submittedAt: submitted ? _clock() : null,
      updatedAt: _clock(),
    ));
    await packageService.rebuild(receipt.id);
  }

  /// Moves receipts out of the main view (or back). Nothing is deleted.
  Future<void> setArchived(
    List<String> ids, {
    required bool archived,
  }) async {
    final now = _clock();
    for (final receipt in await receipts.getByIds(ids)) {
      await receipts.upsert(receipt.copyWith(
        archivedAt: archived ? now : null,
        updatedAt: now,
      ));
    }
  }

  /// Removes the receipt and its whole package folder.
  Future<void> delete(Receipt receipt) async {
    final package = await packages.get(receipt.id);
    await receipts.delete(receipt.id);
    final dir = package?.packageDir;
    if (dir != null && dir.isNotEmpty) await storage.deleteDirectory(dir);
  }
}

class TripCommands {
  TripCommands({
    required this.trips,
    required this.receipts,
    required this.settings,
    required this.packageService,
    required this.idGenerator,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final TripRepository trips;
  final ReceiptRepository receipts;
  final SettingsRepository settings;
  final PackageService packageService;
  final String Function() idGenerator;
  final DateTime Function() _clock;

  Future<Trip> create({
    required String name,
    required String country,
    DateTime? startDate,
    DateTime? endDate,
    String? referenceNotes,
    bool isFavourite = false,
  }) async {
    final now = _clock();
    final folder = PackageNaming.unique(
      PackageNaming.tripFolder(name, startDate),
      await trips.folderNames(),
    );
    final trip = Trip(
      id: idGenerator(),
      name: name.trim(),
      country: country,
      startDate: startDate,
      endDate: endDate,
      referenceNotes: referenceNotes,
      folderName: folder,
      isFavourite: isFavourite,
      createdAt: now,
      updatedAt: now,
    );
    await trips.upsert(trip);
    return trip;
  }

  /// Folder name is fixed at creation, so editing never moves files; the
  /// receipts' generated summaries are refreshed to show the new name.
  Future<void> update(Trip trip) async {
    await trips.upsert(trip.copyWith(updatedAt: _clock()));
    await _rebuildAll(trip.id);
  }

  /// Receipts are kept and moved to Standalone_Expenses.
  Future<void> delete(Trip trip) async {
    final affected = await receipts.search(ReceiptQuery(
      tripId: trip.id,
      archive: ArchiveScope.any,
      limit: 100000,
    ));
    await trips.delete(trip.id); // FK sets receipts.trip_id to NULL.
    for (final receipt in affected) {
      await packageService.rebuild(receipt.id);
    }
    final prefs = await settings.load();
    if (prefs.activeTripId == trip.id) {
      await settings.save(prefs.copyWith(activeTripId: null));
    }
  }

  Future<void> setActive(Trip? trip) async {
    final prefs = await settings.load();
    await settings.save(prefs.copyWith(activeTripId: trip?.id));
  }

  /// Bulk-assign existing receipts to a trip (e.g. ones captured before the
  /// trip was created). They take the trip's country, as when a receipt's
  /// trip is changed on its own screen.
  Future<void> assignReceipts(Trip trip, List<Receipt> toAssign) async {
    for (final receipt in toAssign) {
      await receipts.upsert(receipt.copyWith(
        tripId: trip.id,
        country: trip.country,
        updatedAt: _clock(),
      ));
      await packageService.rebuild(receipt.id);
    }
  }

  /// Receipts in no trip, dated within [trip]'s dates: the ones to offer
  /// when a trip is added after its receipts were scanned.
  Future<List<Receipt>> looseReceiptsFor(Trip trip) async {
    final loose = await looseReceipts();
    return [
      for (final r in loose)
        if (r.transactionDate != null && trip.contains(r.transactionDate!)) r,
    ];
  }

  /// Every receipt not filed under a trip, oldest first.
  Future<List<Receipt>> looseReceipts() async {
    final all = await receipts.search(const ReceiptQuery(
      archive: ArchiveScope.any,
      limit: 100000,
    ));
    final loose = [for (final r in all) if (r.tripId == null) r];
    loose.sort((a, b) => (a.transactionDate ?? a.capturedAt)
        .compareTo(b.transactionDate ?? b.capturedAt));
    return loose;
  }

  Future<void> _rebuildAll(String tripId) async {
    final list = await receipts.search(ReceiptQuery(
      tripId: tripId,
      archive: ArchiveScope.any,
      limit: 100000,
    ));
    for (final receipt in list) {
      await packageService.rebuild(receipt.id);
    }
  }
}

class SettingsCommands {
  SettingsCommands(this.settings);

  final SettingsRepository settings;

  Future<void> save(AppSettings value) => settings.save(value);
}

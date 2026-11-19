import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/capture_receipt.dart';
import '../application/commands.dart';
import '../application/export_service.dart';
import '../application/package_service.dart';
import '../application/translate_items.dart';
import '../data/db/app_database.dart';
import '../data/repositories/sqlite_repositories.dart';
import '../data/services/file_storage_service.dart';
import '../data/services/mlkit_services.dart';
import '../data/services/receipt_image_processor.dart';
import '../data/services/translation_pdf_renderer.dart';
import '../domain/entities/app_settings.dart';
import '../domain/entities/enums.dart';
import '../domain/entities/expense_package.dart';
import '../domain/entities/receipt.dart';
import '../domain/entities/receipt_query.dart';
import '../domain/entities/translation_line.dart';
import '../domain/entities/trip.dart';
import '../domain/repositories/repositories.dart';
import '../domain/services/services.dart';

// ------------------------------------------------------------ infrastructure
// Overridden in main() once the database and folders are ready.

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Override appDatabaseProvider in main()'),
);

final fileStorageProvider = Provider<FileStorageService>(
  (ref) => throw UnimplementedError('Override fileStorageProvider in main()'),
);

const Uuid _uuid = Uuid();
final idGeneratorProvider = Provider<String Function()>((ref) => _uuid.v4);
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

// -------------------------------------------------------------- repositories

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => SqliteReceiptRepository(ref.watch(appDatabaseProvider).db),
);
final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => SqliteTripRepository(ref.watch(appDatabaseProvider).db),
);
final translationRepositoryProvider = Provider<TranslationRepository>(
  (ref) => SqliteTranslationRepository(ref.watch(appDatabaseProvider).db),
);
final merchantMemoryProvider = Provider<MerchantMemoryRepository>(
  (ref) => SqliteMerchantMemoryRepository(ref.watch(appDatabaseProvider).db),
);
final packageRepositoryProvider = Provider<PackageRepository>(
  (ref) => SqlitePackageRepository(ref.watch(appDatabaseProvider).db),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SqliteSettingsRepository(ref.watch(appDatabaseProvider).db),
);

// ------------------------------------------------------------------ services

final imageProcessorProvider =
    Provider<ImageProcessor>((ref) => ReceiptImageProcessor());

final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = MlKitOcrService();
  ref.onDispose(service.dispose);
  return service;
});

final translationServiceProvider = Provider<TranslationService>((ref) {
  final service = MlKitTranslationService();
  ref.onDispose(service.dispose);
  return service;
});

final pdfRendererProvider = Provider<TranslationDocumentRenderer>(
  (ref) => PdfTranslationRenderer(fontLoader: rootBundle.load),
);

// ----------------------------------------------------------------- use cases

final packageServiceProvider = Provider<PackageService>(
  (ref) => PackageService(
    receipts: ref.watch(receiptRepositoryProvider),
    trips: ref.watch(tripRepositoryProvider),
    translations: ref.watch(translationRepositoryProvider),
    packages: ref.watch(packageRepositoryProvider),
    storage: ref.watch(fileStorageProvider),
    pdfRenderer: ref.watch(pdfRendererProvider),
    clock: ref.watch(clockProvider),
  ),
);

final captureReceiptProvider = Provider<CaptureReceiptUseCase>(
  (ref) => CaptureReceiptUseCase(
    receipts: ref.watch(receiptRepositoryProvider),
    trips: ref.watch(tripRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    storage: ref.watch(fileStorageProvider),
    ocr: ref.watch(ocrServiceProvider),
    translation: ref.watch(translationServiceProvider),
    packages: ref.watch(packageServiceProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    imageProcessor: ref.watch(imageProcessorProvider),
    merchantMemory: ref.watch(merchantMemoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final translateItemsProvider = Provider<TranslateItemsUseCase>(
  (ref) => TranslateItemsUseCase(
    receipts: ref.watch(receiptRepositoryProvider),
    translations: ref.watch(translationRepositoryProvider),
    packages: ref.watch(packageRepositoryProvider),
    packageService: ref.watch(packageServiceProvider),
    settings: ref.watch(settingsRepositoryProvider),
    storage: ref.watch(fileStorageProvider),
    ocr: ref.watch(ocrServiceProvider),
    translator: ref.watch(translationServiceProvider),
    imageProcessor: ref.watch(imageProcessorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final receiptCommandsProvider = Provider<ReceiptCommands>(
  (ref) => ReceiptCommands(
    receipts: ref.watch(receiptRepositoryProvider),
    packages: ref.watch(packageRepositoryProvider),
    packageService: ref.watch(packageServiceProvider),
    storage: ref.watch(fileStorageProvider),
    merchantMemory: ref.watch(merchantMemoryProvider),
    clock: ref.watch(clockProvider),
  ),
);

final tripCommandsProvider = Provider<TripCommands>(
  (ref) => TripCommands(
    trips: ref.watch(tripRepositoryProvider),
    receipts: ref.watch(receiptRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    packageService: ref.watch(packageServiceProvider),
    idGenerator: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
  ),
);

final settingsCommandsProvider = Provider<SettingsCommands>(
  (ref) => SettingsCommands(ref.watch(settingsRepositoryProvider)),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    receipts: ref.watch(receiptRepositoryProvider),
    trips: ref.watch(tripRepositoryProvider),
    packages: ref.watch(packageRepositoryProvider),
    storage: ref.watch(fileStorageProvider),
    clock: ref.watch(clockProvider),
  ),
);

// --------------------------------------------------------------- read models

/// Bumped after every write; every query provider watches it, so one call
/// refreshes the whole UI without hand-tracking which providers are stale.
class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataRevisionProvider =
    NotifierProvider<DataRevision, int>(DataRevision.new);

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).stats();
});

final recentReceiptsProvider = FutureProvider<List<Receipt>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).search(const ReceiptQuery(limit: 8));
});

/// Auto-disposed: a new query is created on every keystroke in search.
final receiptSearchProvider =
    FutureProvider.autoDispose.family<List<Receipt>, ReceiptQuery>((ref, query) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).search(query);
});

final receiptByIdProvider =
    FutureProvider.family<Receipt?, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).getById(id);
});

final packageByReceiptProvider =
    FutureProvider.family<ExpensePackage?, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(packageRepositoryProvider).get(id);
});

final packageFilesProvider =
    FutureProvider.family<List<File>, String>((ref, receiptId) async {
  // Watch everything before the first await (Riverpod 3 rule).
  final storage = ref.watch(fileStorageProvider);
  final package = await ref.watch(packageByReceiptProvider(receiptId).future);
  if (package == null) return const [];
  return storage.filesIn(package.packageDir);
});

final translationLinesProvider =
    FutureProvider.family<List<TranslationLine>, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(translationRepositoryProvider).linesFor(id);
});

final tripsProvider = FutureProvider<List<Trip>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(tripRepositoryProvider).getAll();
});

final tripSummariesProvider = FutureProvider<Map<String, TripSummary>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(tripRepositoryProvider).summaries();
});

final settingsProvider = FutureProvider<AppSettings>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(settingsRepositoryProvider).load();
});

final recentMerchantsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).recentMerchants();
});

final recentDescriptionsProvider =
    FutureProvider.family<List<String>, String?>((ref, category) {
  ref.watch(dataRevisionProvider);
  return ref
      .watch(receiptRepositoryProvider)
      .recentDescriptions(category: category);
});

final recentCategoriesProvider =
    FutureProvider.family<List<String>, ClaimType>((ref, type) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).recentCategories(type);
});

final recentCountriesProvider = FutureProvider<List<String>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(receiptRepositoryProvider).recentCountries();
});

final exportFilesProvider = FutureProvider<List<File>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(fileStorageProvider).exports();
});

final storageBytesProvider = FutureProvider<int>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(fileStorageProvider).totalBytes();
});

final modelDownloadedProvider =
    FutureProvider.family<bool, String>((ref, languageCode) {
  ref.watch(dataRevisionProvider);
  return ref.watch(translationServiceProvider).isModelDownloaded(languageCode);
});

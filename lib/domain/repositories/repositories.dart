import '../entities/app_settings.dart';
import '../entities/enums.dart';
import '../entities/expense_package.dart';
import '../entities/receipt.dart';
import '../entities/receipt_query.dart';
import '../entities/translation_line.dart';
import '../entities/trip.dart';
import '../logic/merchant_memory.dart';

/// Repository contracts. The domain and application layers depend only on
/// these; SQLite implementations live in `data/repositories`.

abstract interface class ReceiptRepository {
  Future<Receipt?> getById(String id);

  Future<List<Receipt>> getByIds(List<String> ids);

  Future<List<Receipt>> search(ReceiptQuery query);

  /// Insert or update. Also refreshes the stored [ReceiptStatus].
  Future<void> upsert(Receipt receipt);

  Future<void> delete(String id);

  Future<DashboardStats> stats();

  Future<List<String>> recentMerchants({int limit = 12});

  Future<List<String>> recentDescriptions({String? category, int limit = 8});

  Future<List<String>> recentCategories(ClaimType claimType, {int limit = 5});

  Future<List<String>> recentCountries({int limit = 5});
}

abstract interface class TripRepository {
  Future<List<Trip>> getAll();

  Future<Trip?> getById(String id);

  Future<void> upsert(Trip trip);

  Future<void> delete(String id);

  Future<Set<String>> folderNames();

  Future<Map<String, TripSummary>> summaries();
}

abstract interface class TranslationRepository {
  Future<List<TranslationLine>> linesFor(String receiptId);

  /// Replaces every line for the receipt in one transaction.
  Future<void> replaceLines(String receiptId, List<TranslationLine> lines);

  /// Looks up glossary entries by normalised key. Returns key -> English.
  Future<Map<String, String>> glossaryLookup(
    String sourceLanguage,
    Set<String> keys,
  );

  Future<void> rememberGlossary(
    String sourceLanguage,
    String key,
    String translatedText,
  );
}

abstract interface class MerchantMemoryRepository {
  /// Newest first, so the latest correction wins.
  Future<List<MerchantClue>> all();

  Future<void> remember(List<MerchantClue> clues);
}

abstract interface class PackageRepository {
  Future<ExpensePackage?> get(String receiptId);

  Future<void> upsert(ExpensePackage package);

  Future<Set<String>> allPackageDirs();
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();

  Future<void> save(AppSettings settings);
}

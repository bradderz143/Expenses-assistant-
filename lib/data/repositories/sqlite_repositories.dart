import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/enums.dart';
import '../../domain/entities/expense_package.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/receipt_query.dart';
import '../../domain/entities/translation_line.dart';
import '../../domain/entities/trip.dart';
import '../../domain/logic/formatting.dart';
import '../../domain/reference/currencies.dart';
import '../../domain/logic/merchant_memory.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/value_objects/money.dart';
import '../db/mappers.dart';

/// Update-then-insert. `INSERT OR REPLACE` is avoided on purpose: REPLACE
/// deletes the old row first, which would fire ON DELETE CASCADE and wipe the
/// receipt's translations and package record.
Future<void> _upsertRow(
  DatabaseExecutor db,
  String table,
  String keyColumn,
  Map<String, Object?> row,
) async {
  final updated = await db.update(
    table,
    row,
    where: '$keyColumn = ?',
    whereArgs: [row[keyColumn]],
  );
  if (updated == 0) await db.insert(table, row);
}

String _escapeLike(String input) => input
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');

int _intOf(Object? v) => (v as int?) ?? 0;

// ------------------------------------------------------------------ receipts

class SqliteReceiptRepository implements ReceiptRepository {
  SqliteReceiptRepository(this._db);

  final Database _db;

  @override
  Future<Receipt?> getById(String id) async {
    final rows = await _db.query('receipts', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Mappers.receiptFromRow(rows.first);
  }

  @override
  Future<List<Receipt>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.query(
      'receipts',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'transaction_date ASC, captured_at ASC',
    );
    return rows.map(Mappers.receiptFromRow).toList();
  }

  @override
  Future<List<Receipt>> search(ReceiptQuery query) async {
    final where = <String>[];
    final args = <Object?>[];

    final text = query.text?.trim();
    if (text != null && text.isNotEmpty) {
      final like = '%${_escapeLike(text)}%';
      const escape = r" ESCAPE '\'";
      final clauses = <String>[
        'r.merchant LIKE ?$escape',
        'r.description LIKE ?$escape',
        'r.country LIKE ?$escape',
        'r.category LIKE ?$escape',
        't.name LIKE ?$escape',
      ];
      args.addAll(List.filled(clauses.length, like));
      if (RegExp(r'^[\d.,]+$').hasMatch(text)) {
        _addAmountClauses(text, clauses, args);
      }
      where.add('(${clauses.join(' OR ')})');
    }
    if (query.tripId != null) {
      where.add('r.trip_id = ?');
      args.add(query.tripId);
    }
    if (query.category != null) {
      where.add('r.category = ?');
      args.add(query.category);
    }
    if (query.status != null) {
      where.add('r.status = ?');
      args.add(query.status!.name);
    }
    switch (query.archive) {
      case ArchiveScope.active:
        where.add('r.archived_at IS NULL');
      case ArchiveScope.archived:
        where.add('r.archived_at IS NOT NULL');
      case ArchiveScope.any:
        break;
    }
    if (query.from != null) {
      where.add('r.transaction_date >= ?');
      args.add(Formatting.isoDate(query.from!));
    }
    if (query.to != null) {
      where.add('r.transaction_date <= ?');
      args.add(Formatting.isoDate(query.to!));
    }
    args.add(query.limit);

    final rows = await _db.rawQuery(
      'SELECT r.* FROM receipts r '
      'LEFT JOIN trips t ON t.id = r.trip_id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
      'ORDER BY COALESCE(r.transaction_date, substr(r.captured_at, 1, 10)) DESC, '
      'r.captured_at DESC LIMIT ?',
      args,
    );
    return rows.map(Mappers.receiptFromRow).toList();
  }

  /// "428.5" matches 428.50; "428" matches 428.00 to 428.99. Each currency
  /// is compared in its own decimal places (JPY 0, MXN 2, KWD 3).
  static void _addAmountClauses(
    String text,
    List<String> clauses,
    List<Object?> args,
  ) {
    final wholeNumber = !text.contains(RegExp('[.,]'));
    final odd = [...Currencies.zeroDecimal, ...Currencies.threeDecimal];
    String inList(Iterable<String> codes) =>
        List.filled(codes.length, '?').join(', ');

    void add(int exponent, String currencyFilter, List<String> codes) {
      final minor = Money.parseMinor(text, exponent: exponent);
      if (minor == null) return;
      clauses.add('(r.amount_minor = ? AND $currencyFilter)');
      args
        ..add(minor)
        ..addAll(codes);
      if (wholeNumber && exponent > 0) {
        final divisor = exponent == 3 ? 1000 : 100;
        clauses.add('((r.amount_minor / $divisor) = ? AND $currencyFilter)');
        args
          ..add(int.parse(text))
          ..addAll(codes);
      }
    }

    add(2, 'r.currency NOT IN (${inList(odd)})', odd);
    add(0, 'r.currency IN (${inList(Currencies.zeroDecimal)})',
        Currencies.zeroDecimal.toList());
    add(3, 'r.currency IN (${inList(Currencies.threeDecimal)})',
        Currencies.threeDecimal.toList());
  }

  @override
  Future<void> upsert(Receipt receipt) =>
      _upsertRow(_db, 'receipts', 'id', Mappers.receiptToRow(receipt));

  @override
  Future<void> delete(String id) =>
      _db.delete('receipts', where: 'id = ?', whereArgs: [id]);

  @override
  Future<DashboardStats> stats() async {
    final rows = await _db.rawQuery('''
      SELECT
        COUNT(*) AS total,
        SUM(CASE WHEN status = 'needsClassification' THEN 1 ELSE 0 END) AS nc,
        SUM(CASE WHEN status = 'needsTranslation' THEN 1 ELSE 0 END) AS nt,
        SUM(CASE WHEN status = 'ready' THEN 1 ELSE 0 END) AS ready,
        SUM(CASE WHEN status = 'submitted' THEN 1 ELSE 0 END) AS submitted
      FROM receipts
      WHERE archived_at IS NULL
    ''');
    final row = rows.first;
    return DashboardStats(
      total: _intOf(row['total']),
      needsClassification: _intOf(row['nc']),
      needsTranslation: _intOf(row['nt']),
      ready: _intOf(row['ready']),
      submitted: _intOf(row['submitted']),
    );
  }

  Future<List<String>> _recentDistinct(
    String column, {
    required int limit,
    String? extraWhere,
    List<Object?> extraArgs = const [],
  }) async {
    final rows = await _db.rawQuery(
      'SELECT $column AS value, MAX(updated_at) AS last_used FROM receipts '
      "WHERE $column IS NOT NULL AND $column != '' "
      '${extraWhere == null ? '' : 'AND $extraWhere '}'
      'GROUP BY $column ORDER BY last_used DESC LIMIT ?',
      [...extraArgs, limit],
    );
    return [for (final r in rows) r['value']! as String];
  }

  @override
  Future<List<String>> recentMerchants({int limit = 12}) =>
      _recentDistinct('merchant', limit: limit);

  @override
  Future<List<String>> recentDescriptions({String? category, int limit = 8}) =>
      _recentDistinct(
        'description',
        limit: limit,
        extraWhere: category == null ? null : 'category = ?',
        extraArgs: category == null ? const [] : [category],
      );

  @override
  Future<List<String>> recentCategories(ClaimType claimType, {int limit = 5}) =>
      _recentDistinct(
        'category',
        limit: limit,
        extraWhere: 'claim_type = ?',
        extraArgs: [claimType.name],
      );

  @override
  Future<List<String>> recentCountries({int limit = 5}) =>
      _recentDistinct('country', limit: limit);
}

// --------------------------------------------------------------------- trips

class SqliteTripRepository implements TripRepository {
  SqliteTripRepository(this._db);

  final Database _db;

  @override
  Future<List<Trip>> getAll() async {
    final rows = await _db.query(
      'trips',
      orderBy: 'is_favourite DESC, COALESCE(start_date, created_at) DESC',
    );
    return rows.map(Mappers.tripFromRow).toList();
  }

  @override
  Future<Trip?> getById(String id) async {
    final rows = await _db.query('trips', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Mappers.tripFromRow(rows.first);
  }

  @override
  Future<void> upsert(Trip trip) =>
      _upsertRow(_db, 'trips', 'id', Mappers.tripToRow(trip));

  @override
  Future<void> delete(String id) =>
      _db.delete('trips', where: 'id = ?', whereArgs: [id]);

  @override
  Future<Set<String>> folderNames() async {
    final rows = await _db.query('trips', columns: ['folder_name']);
    return {for (final r in rows) r['folder_name']! as String};
  }

  @override
  Future<Map<String, TripSummary>> summaries() async {
    final rows = await _db.rawQuery('''
      SELECT trip_id, currency, COUNT(*) AS n, SUM(amount_minor) AS total
      FROM receipts WHERE trip_id IS NOT NULL
      GROUP BY trip_id, currency
    ''');
    final counts = <String, int>{};
    final totals = <String, Map<String, int>>{};
    for (final r in rows) {
      final tripId = r['trip_id']! as String;
      counts[tripId] = (counts[tripId] ?? 0) + _intOf(r['n']);
      (totals[tripId] ??= {})[r['currency']! as String] = _intOf(r['total']);
    }
    return {
      for (final id in counts.keys)
        id: TripSummary(receiptCount: counts[id]!, totals: totals[id] ?? {}),
    };
  }
}

// -------------------------------------------------------------- translations

class SqliteTranslationRepository implements TranslationRepository {
  SqliteTranslationRepository(this._db);

  final Database _db;

  @override
  Future<List<TranslationLine>> linesFor(String receiptId) async {
    final rows = await _db.query(
      'translations',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
      orderBy: 'line_no ASC',
    );
    return rows.map(Mappers.lineFromRow).toList();
  }

  @override
  Future<void> replaceLines(String receiptId, List<TranslationLine> lines) {
    return _db.transaction((txn) async {
      await txn.delete(
        'translations',
        where: 'receipt_id = ?',
        whereArgs: [receiptId],
      );
      for (final line in lines) {
        await txn.insert('translations', Mappers.lineToRow(receiptId, line));
      }
    });
  }

  @override
  Future<Map<String, String>> glossaryLookup(
    String sourceLanguage,
    Set<String> keys,
  ) async {
    if (keys.isEmpty) return const {};
    final list = keys.toList();
    final placeholders = List.filled(list.length, '?').join(', ');
    final rows = await _db.query(
      'translation_glossary',
      columns: ['source_key', 'translated_text'],
      where: 'source_language = ? AND source_key IN ($placeholders)',
      whereArgs: [sourceLanguage, ...list],
    );
    return {
      for (final r in rows)
        r['source_key']! as String: r['translated_text']! as String,
    };
  }

  @override
  Future<void> rememberGlossary(
    String sourceLanguage,
    String key,
    String translatedText,
  ) {
    return _db.transaction((txn) async {
      final now = Mappers.timestamp(DateTime.now());
      final updated = await txn.rawUpdate(
        'UPDATE translation_glossary '
        'SET translated_text = ?, use_count = use_count + 1, updated_at = ? '
        'WHERE source_language = ? AND source_key = ?',
        [translatedText, now, sourceLanguage, key],
      );
      if (updated == 0) {
        await txn.insert('translation_glossary', {
          'source_language': sourceLanguage,
          'source_key': key,
          'translated_text': translatedText,
          'use_count': 1,
          'updated_at': now,
        });
      }
    });
  }
}

// ---------------------------------------------------------- merchant memory

class SqliteMerchantMemoryRepository implements MerchantMemoryRepository {
  SqliteMerchantMemoryRepository(this._db);

  final Database _db;

  @override
  Future<List<MerchantClue>> all() async {
    final rows = await _db.query(
      'merchant_memory',
      orderBy: 'updated_at DESC',
    );
    return [
      for (final r in rows)
        MerchantClue(
          ClueKind.values.firstWhere(
            (k) => k.name == r['kind'],
            orElse: () => ClueKind.printed,
          ),
          r['clue']! as String,
          r['merchant']! as String,
        ),
    ];
  }

  @override
  Future<void> remember(List<MerchantClue> clues) {
    if (clues.isEmpty) return Future.value();
    return _db.transaction((txn) async {
      final now = Mappers.timestamp(DateTime.now());
      for (final c in clues) {
        final updated = await txn.rawUpdate(
          'UPDATE merchant_memory SET merchant = ?, updated_at = ? '
          'WHERE kind = ? AND clue = ?',
          [c.merchant, now, c.kind.name, c.key],
        );
        if (updated == 0) {
          await txn.insert('merchant_memory', {
            'kind': c.kind.name,
            'clue': c.key,
            'merchant': c.merchant,
            'updated_at': now,
          });
        }
      }
    });
  }
}

// ------------------------------------------------------------------ packages

class SqlitePackageRepository implements PackageRepository {
  SqlitePackageRepository(this._db);

  final Database _db;

  @override
  Future<ExpensePackage?> get(String receiptId) async {
    final rows = await _db.query(
      'expense_packages',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    return rows.isEmpty ? null : Mappers.packageFromRow(rows.first);
  }

  @override
  Future<void> upsert(ExpensePackage package) => _upsertRow(
        _db,
        'expense_packages',
        'receipt_id',
        Mappers.packageToRow(package),
      );

  @override
  Future<Set<String>> allPackageDirs() async {
    final rows = await _db.query('expense_packages', columns: ['package_dir']);
    return {for (final r in rows) r['package_dir']! as String};
  }
}

// ------------------------------------------------------------------ settings

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Database _db;

  static const _defaultCountry = 'default_country';
  static const _defaultClaimType = 'default_claim_type';
  static const _activeTripId = 'active_trip_id';
  static const _favouriteCountries = 'favourite_countries';
  static const _wifiOnly = 'wifi_only_model_downloads';

  @override
  Future<AppSettings> load() async {
    final rows = await _db.query('app_settings');
    final values = {
      for (final r in rows)
        r['setting_key']! as String: r['setting_value']! as String,
    };
    const defaults = AppSettings();
    final favouritesJson = values[_favouriteCountries];
    final activeTrip = values[_activeTripId];
    return AppSettings(
      defaultCountry: values[_defaultCountry] ?? defaults.defaultCountry,
      defaultClaimType: ClaimType.fromName(values[_defaultClaimType]),
      activeTripId: activeTrip == null || activeTrip.isEmpty ? null : activeTrip,
      favouriteCountries: favouritesJson == null
          ? defaults.favouriteCountries
          : (jsonDecode(favouritesJson) as List<dynamic>).cast<String>(),
      wifiOnlyModelDownloads: values[_wifiOnly] == 'true',
    );
  }

  @override
  Future<void> save(AppSettings settings) {
    final values = {
      _defaultCountry: settings.defaultCountry,
      _defaultClaimType: settings.defaultClaimType.name,
      _activeTripId: settings.activeTripId ?? '',
      _favouriteCountries: jsonEncode(settings.favouriteCountries),
      _wifiOnly: settings.wifiOnlyModelDownloads.toString(),
    };
    return _db.transaction((txn) async {
      for (final entry in values.entries) {
        await _upsertRow(txn, 'app_settings', 'setting_key', {
          'setting_key': entry.key,
          'setting_value': entry.value,
        });
      }
    });
  }
}

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// Owns the SQLite connection and runs migrations.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const String fileName = 'expenses.db';

  /// [factory] and [path] are injectable so tests can use
  /// `databaseFactoryFfi` with `inMemoryDatabasePath`.
  static Future<AppDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final dbPath =
        path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: Migrations.latestVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _migrate(db, 0, version);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _migrate(db, oldVersion, newVersion);
        },
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    final batch = db.batch();
    for (var version = from + 1; version <= to; version++) {
      final statements = Migrations.steps[version];
      if (statements == null) {
        throw StateError('Missing migration for schema version $version');
      }
      for (final sql in statements) {
        batch.execute(sql);
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();
}

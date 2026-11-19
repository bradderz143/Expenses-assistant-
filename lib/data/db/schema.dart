/// Versioned schema. Never edit a released step: add a new version instead.
///
/// Uses only SQL that works on SQLite 3.8+ (Android 7 ships 3.9), so no
/// UPSERT, window functions or RETURNING.
class Migrations {
  Migrations._();

  static const int latestVersion = 4;

  static final Map<int, List<String>> steps = {
    1: _v1,
    2: _v2,
    3: _v3,
    4: _v4,
  };

  static final List<String> _v1 = [
    '''
    CREATE TABLE trips (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      country TEXT NOT NULL,
      start_date TEXT,
      end_date TEXT,
      reference_notes TEXT,
      folder_name TEXT NOT NULL UNIQUE,
      is_favourite INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE receipts (
      id TEXT PRIMARY KEY NOT NULL,
      trip_id TEXT REFERENCES trips(id) ON DELETE SET NULL,
      merchant TEXT,
      transaction_date TEXT,
      amount_minor INTEGER,
      currency TEXT NOT NULL,
      country TEXT NOT NULL,
      claim_type TEXT NOT NULL,
      category TEXT,
      meal_type TEXT,
      description TEXT,
      raw_ocr_text TEXT NOT NULL DEFAULT '',
      detected_language TEXT,
      translation_status TEXT NOT NULL,
      status TEXT NOT NULL,
      original_image_path TEXT NOT NULL,
      captured_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      submitted_at TEXT
    )
    ''',
    'CREATE INDEX idx_receipts_date ON receipts(transaction_date)',
    'CREATE INDEX idx_receipts_trip ON receipts(trip_id)',
    'CREATE INDEX idx_receipts_status ON receipts(status)',
    'CREATE INDEX idx_receipts_category ON receipts(category)',
    'CREATE INDEX idx_receipts_merchant ON receipts(merchant COLLATE NOCASE)',
    '''
    CREATE TABLE expense_packages (
      receipt_id TEXT PRIMARY KEY NOT NULL
        REFERENCES receipts(id) ON DELETE CASCADE,
      package_dir TEXT NOT NULL UNIQUE,
      has_crop INTEGER NOT NULL DEFAULT 0,
      has_translation INTEGER NOT NULL DEFAULT 0,
      built_at TEXT
    )
    ''',
    '''
    CREATE TABLE translations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      receipt_id TEXT NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
      line_no INTEGER NOT NULL,
      quantity TEXT,
      original_text TEXT NOT NULL,
      translated_text TEXT NOT NULL,
      amount_text TEXT,
      source_language TEXT,
      engine TEXT NOT NULL,
      UNIQUE (receipt_id, line_no)
    )
    ''',
    'CREATE INDEX idx_translations_receipt ON translations(receipt_id)',
    '''
    CREATE TABLE translation_glossary (
      source_language TEXT NOT NULL,
      source_key TEXT NOT NULL,
      translated_text TEXT NOT NULL,
      use_count INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (source_language, source_key)
    )
    ''',
    '''
    CREATE TABLE app_settings (
      setting_key TEXT PRIMARY KEY NOT NULL,
      setting_value TEXT NOT NULL
    )
    ''',
    ..._seedGlossary,
  ];

  /// v2: archiving, food/drink grouping of translated items, and a few more
  /// glossary entries.
  static final List<String> _v2 = [
    'ALTER TABLE receipts ADD COLUMN archived_at TEXT',
    'CREATE INDEX idx_receipts_archived ON receipts(archived_at)',
    "ALTER TABLE translations ADD COLUMN category TEXT NOT NULL DEFAULT 'food'",
    _g('coca cola bot', 'Coca-Cola (bottle)'),
    _g('coca cola', 'Coca-Cola'),
    _g('coca zero bot', 'Coca-Cola Zero (bottle)'),
    _g('coca zero', 'Coca-Cola Zero'),
    _g('coca cola zero', 'Coca-Cola Zero'),
    _g('agua bot', 'Bottled water'),
    _g('cerveza bot', 'Beer (bottle)'),
  ];

  /// Merchant names learned from the user's corrections.
  static final List<String> _v3 = [
    '''
    CREATE TABLE merchant_memory (
      kind TEXT NOT NULL,
      clue TEXT NOT NULL,
      merchant TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (kind, clue)
    )
    ''',
  ];

  /// What the scan was not sure of (ScanCheck names, comma-separated), until
  /// the user has checked the receipt.
  static final List<String> _v4 = [
    'ALTER TABLE receipts ADD COLUMN to_check TEXT',
  ];

  /// Common Mexican menu items where literal machine translation is poor
  /// ("al pastor" is not "shepherd-style"). Keys are TextNormaliser.glossaryKey.
  static final List<String> _seedGlossary = [
    _g('tacos al pastor', 'Pork tacos (al pastor)'),
    _g('taco al pastor', 'Pork taco (al pastor)'),
    _g('agua mineral', 'Mineral water'),
    _g('agua natural', 'Still water'),
    _g('agua embotellada', 'Bottled water'),
    _g('agua de jamaica', 'Hibiscus drink'),
    _g('agua de horchata', 'Horchata (rice drink)'),
    _g('agua fresca', 'Fresh fruit drink'),
    _g('cafe americano', 'Americano coffee'),
    _g('americano', 'Americano coffee'),
    _g('cafe de olla', 'Spiced pot coffee'),
    _g('cafe con leche', 'White coffee'),
    _g('capuchino', 'Cappuccino'),
    _g('te', 'Tea'),
    _g('refresco', 'Soft drink'),
    _g('cerveza', 'Beer'),
    _g('jugo de naranja', 'Orange juice'),
    _g('chilaquiles', 'Chilaquiles (tortilla chips in salsa)'),
    _g('molletes', 'Molletes (bean and cheese toast)'),
    _g('huevos rancheros', 'Ranch-style eggs'),
    _g('huevos a la mexicana', 'Mexican-style scrambled eggs'),
    _g('enchiladas', 'Enchiladas'),
    _g('quesadilla', 'Quesadilla'),
    _g('sopa de tortilla', 'Tortilla soup'),
    _g('arrachera', 'Skirt steak'),
    _g('pechuga de pollo', 'Chicken breast'),
    _g('pan dulce', 'Sweet bread'),
    _g('ensalada', 'Salad'),
    _g('postre', 'Dessert'),
    _g('comida corrida', 'Set lunch menu'),
    _g('menu del dia', 'Set menu of the day'),
    _g('desayuno', 'Breakfast'),
  ];

  static const String _seedTimestamp = '2026-01-01T00:00:00.000Z';

  static String _g(String key, String english) =>
      'INSERT OR IGNORE INTO translation_glossary '
      '(source_language, source_key, translated_text, use_count, updated_at) '
      "VALUES ('es', '$key', '${english.replaceAll("'", "''")}', 0, "
      "'$_seedTimestamp')";
}

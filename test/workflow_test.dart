import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:expense_assistant/application/capture_receipt.dart';
import 'package:expense_assistant/application/commands.dart';
import 'package:expense_assistant/application/export_service.dart';
import 'package:expense_assistant/application/package_service.dart';
import 'package:expense_assistant/application/translate_items.dart';
import 'package:expense_assistant/data/db/app_database.dart';
import 'package:expense_assistant/data/db/schema.dart';
import 'package:expense_assistant/data/repositories/sqlite_repositories.dart';
import 'package:expense_assistant/data/services/file_storage_service.dart';
import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/entities/receipt.dart';
import 'package:expense_assistant/domain/entities/receipt_query.dart';
import 'package:expense_assistant/domain/entities/translation_line.dart';
import 'package:expense_assistant/domain/entities/trip.dart';
import 'package:expense_assistant/domain/logic/item_area_detector.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'domain_logic_test.dart' show elFogonRows;
import 'scan_misread_test.dart' show misread;

/// Records what the capture step asks of the image processor.
class FakeImageProcessor implements ImageProcessor {
  FakeImageProcessor({required this.paperFound});

  final bool paperFound;
  final List<TextBlock> trims = [];

  @override
  Future<bool> cropToReceipt(String sourcePath, String destPath) async {
    await File(sourcePath).copy(destPath);
    return paperFound;
  }

  @override
  Future<bool> trimToText(String path, TextBlock text) async {
    trims.add(text);
    return true;
  }

  @override
  Future<void> normalise(String sourcePath, String destPath,
          {int maxSide = 2400}) async =>
      File(sourcePath).copy(destPath);

  @override
  Future<void> crop(
    String sourcePath,
    String destPath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) async =>
      File(sourcePath).copy(destPath);
}

class FakeOcr implements OcrService {
  final List<OcrResult> queue = [];

  void enqueueRows(List<String> rows) => queue.add(OcrResult(
        text: rows.join('\n'),
        lines: [for (final r in rows) OcrLine(text: r)],
      ));

  @override
  Future<OcrResult> recognise(String imagePath) async =>
      queue.isEmpty ? OcrResult.empty : queue.removeAt(0);

  @override
  Future<void> dispose() async {}
}

class FakeTranslation implements TranslationService {
  @override
  Future<String?> identifyLanguage(String text) async =>
      text.trim().isEmpty ? null : 'es';

  @override
  bool supports(String languageCode) => true;

  @override
  Future<bool> isModelDownloaded(String languageCode) async => true;

  @override
  Future<bool> downloadModel(String languageCode, {bool wifiOnly = false}) async =>
      true;

  @override
  Future<bool> deleteModel(String languageCode) async => true;

  @override
  Future<List<String>> translateAll(
    List<String> texts, {
    required String from,
    String to = 'en',
  }) async =>
      [for (final t in texts) 'EN:$t'];

  @override
  Future<void> dispose() async {}
}

class FakePdf implements TranslationDocumentRenderer {
  int renders = 0;

  @override
  Future<Uint8List> render({
    required Receipt receipt,
    required List<TranslationLine> lines,
    required DateTime generatedAt,
    Trip? trip,
    Uint8List? cropImage,
  }) async {
    renders++;
    return Uint8List.fromList('%PDF-1.4 fake'.codeUnits);
  }
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late FileStorageService storage;
  late FakeOcr ocr;
  late FakePdf pdf;
  late SqliteReceiptRepository receipts;
  late SqliteTripRepository trips;
  late SqliteTranslationRepository translations;
  late SqlitePackageRepository packages;
  late SqliteSettingsRepository settings;
  late PackageService packageService;
  var ids = 0;
  DateTime clock() => DateTime(2026, 11, 4, 14, 40);
  String nextId() => 'id-${++ids}';

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await AppDatabase.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    temp = await Directory.systemTemp.createTemp('expense_test');
    storage = FileStorageService(Directory(p.join(temp.path, 'Expenses')));
    await storage.ensureStructure();
    ocr = FakeOcr();
    pdf = FakePdf();
    receipts = SqliteReceiptRepository(db.db);
    trips = SqliteTripRepository(db.db);
    translations = SqliteTranslationRepository(db.db);
    packages = SqlitePackageRepository(db.db);
    settings = SqliteSettingsRepository(db.db);
    packageService = PackageService(
      receipts: receipts,
      trips: trips,
      translations: translations,
      packages: packages,
      storage: storage,
      pdfRenderer: pdf,
      clock: clock,
    );
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  test('capture -> classify -> translate -> move to trip -> export', () async {
    // --- capture
    final photo = File(p.join(temp.path, 'IMG_0001.jpg'))
      ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
    ocr.enqueueRows(elFogonRows);
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final outcome = await capture(photo.path);
    var receipt = outcome.receipt;

    expect(receipt.merchant, 'El Fogon');
    expect(receipt.amountMinor, 42850);
    expect(receipt.currency, 'MXN');
    expect(receipt.country, 'Mexico');
    expect(receipt.mealType, MealType.lunch); // from the 14:35 on the ticket
    expect(receipt.translationStatus, TranslationStatus.pending);
    expect(receipt.status, ReceiptStatus.needsClassification);
    const folder = 'Standalone_Expenses/2026-11-04_ElFogon_428.50MXN';
    expect(receipt.originalImagePath, '$folder/original_receipt.jpg');
    // Original stored byte-for-byte.
    expect(
      File(storage.absolute(receipt.originalImagePath)).readAsBytesSync(),
      photo.readAsBytesSync(),
    );
    expect(File(storage.absolute('$folder/metadata.json')).existsSync(), isTrue);
    expect(File(storage.absolute('$folder/claim_summary.txt')).existsSync(), isTrue);

    // --- classify
    final commands = ReceiptCommands(
      receipts: receipts,
      packages: packages,
      packageService: packageService,
      storage: storage,
      clock: clock,
    );
    receipt = await commands.saveDetails(receipt.copyWith(
      category: 'Meals Overseas',
      description: 'Lunch whilst attending ACS workshop',
    ));
    expect(receipt.status, ReceiptStatus.needsTranslation);

    // --- crop + translate
    final crop = File(p.join(temp.path, 'crop.jpg'))..writeAsBytesSync([1, 2, 3]);
    ocr.enqueueRows([
      '4 TACOS AL PASTOR 220.00',
      '2 AGUA MINERAL 70.00',
      '1 PAN DE ELOTE 45.00',
      'SUBTOTAL 335.00',
    ]);
    final translate = TranslateItemsUseCase(
      receipts: receipts,
      translations: translations,
      packages: packages,
      packageService: packageService,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translator: FakeTranslation(),
      clock: clock,
    );
    final draft = await translate.prepare(receipt: receipt, croppedImagePath: crop.path);
    expect(draft.sourceLanguage, 'es');
    expect(draft.lines.map((l) => l.translatedText).toList(), [
      'Pork tacos (al pastor)', // seeded glossary
      'Mineral water', // seeded glossary
      'EN:PAN DE ELOTE', // on-device model
    ]);
    expect(draft.lines[2].engine, TranslationEngine.onDevice);

    // User corrects the machine translation; it should be learned.
    final reviewed = [
      ...draft.lines.take(2),
      draft.lines[2].copyWith(
        translatedText: 'Sweetcorn bread',
        engine: TranslationEngine.manual,
      ),
    ];
    await translate.save(receipt: receipt, sourceLanguage: 'es', lines: reviewed);
    receipt = (await receipts.getById(receipt.id))!;
    expect(receipt.status, ReceiptStatus.ready);
    expect(File(storage.absolute('$folder/items_crop.jpg')).existsSync(), isTrue);
    expect(File(storage.absolute('$folder/translated_items.pdf')).existsSync(), isTrue);
    expect(
      File(storage.absolute('$folder/translated_items.txt')).readAsStringSync(),
      contains('Sweetcorn bread'),
    );
    expect(
      File(storage.absolute('$folder/claim_summary.txt')).readAsStringSync(),
      endsWith('original_receipt.jpg\ntranslated_items.pdf\n'),
    );
    expect(
      await translations.glossaryLookup('es', {'pan de elote'}),
      {'pan de elote': 'Sweetcorn bread'},
    );

    // --- move into a trip
    final tripCommands = TripCommands(
      trips: trips,
      receipts: receipts,
      settings: settings,
      packageService: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final trip = await tripCommands.create(
      name: 'Caracas ACS Workshop',
      country: 'Venezuela',
      startDate: DateTime(2026, 11, 9),
      endDate: DateTime(2026, 11, 13),
    );
    expect(trip.folderName, 'Caracas_ACS_Workshop_2026');
    await tripCommands.assignReceipts(trip, [receipt]);
    receipt = (await receipts.getById(receipt.id))!;
    const tripFolder =
        'Trips/Caracas_ACS_Workshop_2026/2026-11-04_ElFogon_428.50MXN';
    expect(receipt.originalImagePath, '$tripFolder/original_receipt.jpg');
    expect(Directory(storage.absolute(folder)).existsSync(), isFalse);
    expect(File(storage.absolute('$tripFolder/translated_items.pdf')).existsSync(), isTrue);

    // --- search
    Future<int> count(String text) async =>
        (await receipts.search(ReceiptQuery(text: text))).length;
    expect(await count('fogon'), 1);
    expect(await count('428.50'), 1);
    expect(await count('428'), 1);
    expect(await count('Caracas'), 1); // trip name
    expect(await count('Accra'), 0);
    expect((await receipts.stats()).ready, 1);

    // --- export: flat ZIP, named after the trip and its start date
    final export = ExportService(
      receipts: receipts,
      trips: trips,
      packages: packages,
      storage: storage,
      clock: clock,
    );
    final result = await export.export(TripScope(trip.id));
    expect(p.basename(result.file.path), 'Caracas_ACS_Workshop_2026-11-09.zip');
    expect(result.receiptCount, 1);
    expect(result.translatedCount, 1);
    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    expect(
      zip.map((f) => f.name).toSet(),
      {
        '2026-11-04_428.50MXN.jpg',
        '2026-11-04_428.50MXN_translated.pdf',
      },
    );
    expect(
      zip.firstWhere((f) => f.name.endsWith('.jpg')).content,
      photo.readAsBytesSync(),
    );

    // --- delete trip: receipt survives, folder returns to standalone
    await tripCommands.delete(trip);
    receipt = (await receipts.getById(receipt.id))!;
    expect(receipt.tripId, isNull);
    expect(receipt.originalImagePath, '$folder/original_receipt.jpg');
    expect(Directory(storage.absolute('Trips/Caracas_ACS_Workshop_2026')).existsSync(),
        isFalse);
  });

  test('two receipts with the same name get distinct folders', () async {
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final a = File(p.join(temp.path, 'a.jpg'))..writeAsBytesSync([1]);
    final b = File(p.join(temp.path, 'b.jpg'))..writeAsBytesSync([2]);
    ocr
      ..enqueueRows(elFogonRows)
      ..enqueueRows(elFogonRows);
    final first = (await capture(a.path)).receipt;
    final second = (await capture(b.path)).receipt;
    expect(p.dirname(first.originalImagePath),
        'Standalone_Expenses/2026-11-04_ElFogon_428.50MXN');
    expect(p.dirname(second.originalImagePath),
        'Standalone_Expenses/2026-11-04_ElFogon_428.50MXN_2');

    // Re-saving the second must not rename it back onto the first.
    final resaved = await ReceiptCommands(
      receipts: receipts,
      packages: packages,
      packageService: packageService,
      storage: storage,
      clock: clock,
    ).saveDetails(second.copyWith(description: 'Dinner'));
    expect(p.dirname(resaved.originalImagePath),
        'Standalone_Expenses/2026-11-04_ElFogon_428.50MXN_2');
  });

  test('export names: duplicates get a suffix, untranslated has no sheet',
      () async {
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final a = File(p.join(temp.path, 'a.jpg'))..writeAsBytesSync([1]);
    final b = File(p.join(temp.path, 'b.jpg'))..writeAsBytesSync([2]);
    ocr
      ..enqueueRows(elFogonRows)
      ..enqueueRows(elFogonRows);
    await capture(a.path);
    await capture(b.path);

    final export = ExportService(
      receipts: receipts,
      trips: trips,
      packages: packages,
      storage: storage,
      clock: clock,
    );
    final result = await export.export(const UnassignedScope());
    expect(p.basename(result.file.path), 'Expenses_2026-11-04.zip');
    expect(result.receiptCount, 2);
    expect(result.translatedCount, 0);
    final zip = ZipDecoder().decodeBytes(result.file.readAsBytesSync());
    expect(
      zip.map((f) => f.name).toSet(),
      {'2026-11-04_428.50MXN.jpg', '2026-11-04_428.50MXN_2.jpg'},
    );
  });

  test('exporting nothing is an error', () async {
    final export = ExportService(
      receipts: receipts,
      trips: trips,
      packages: packages,
      storage: storage,
      clock: clock,
    );
    expect(
      () => export.export(const UnassignedScope()),
      throwsA(isA<ExportException>()),
    );
  });

  test('OCR failure still keeps the photo', () async {
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr, // empty queue -> no text
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final photo = File(p.join(temp.path, 'blurry.jpg'))..writeAsBytesSync([9, 9]);
    final outcome = await capture(photo.path);
    expect(outcome.amountFound, isFalse);
    expect(File(storage.absolute(outcome.receipt.originalImagePath)).existsSync(),
        isTrue);
    expect(outcome.receipt.transactionDate, DateTime(2026, 11, 4)); // today
  });

  group('what the scan was not sure of', () {
    CaptureReceiptUseCase capturer({ImageProcessor? images}) =>
        CaptureReceiptUseCase(
          receipts: receipts,
          trips: trips,
          settings: settings,
          storage: storage,
          ocr: ocr,
          translation: FakeTranslation(),
          packages: packageService,
          idGenerator: nextId,
          imageProcessor: images,
          clock: clock,
        );
    ReceiptCommands commands() => ReceiptCommands(
          receipts: receipts,
          packages: packages,
          packageService: packageService,
          storage: storage,
          clock: clock,
        );
    File photo(String name) =>
        File(p.join(temp.path, name))..writeAsBytesSync([1, 2, 3]);

    test('a clean read has nothing to check', () async {
      ocr.enqueueRows(elFogonRows);
      final outcome = await capturer()(photo('clean.jpg').path);
      expect(outcome.receipt.toCheck, isEmpty);
      expect(outcome.dateFound, isTrue);
      expect(outcome.amountFound, isTrue);
      expect(outcome.readNote, isNull);
    });

    test('unread date falls back to today but is flagged, and stays flagged '
        'until saved', () async {
      // the restaurant bill as it was really scanned: the total, the words and the
      // date unreadable, no ticket number.
      ocr.enqueueRows(misread({
        r'Total  $3,760.00': 'Tota1  S3,76O.OO',
        '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)':
            '(**IRES MIL SEIECIENIOS SESENTA PESOS OO/1OO **)',
        'Total de productos : 24': 'Total de productcs : 24',
        '28/07/2026 14:42': "28/0'/2026 14:42",
        'Ticket: 20260728-001-100001-00001': null,
      }));
      final outcome = await capturer()(photo('bill.jpg').path);
      var receipt = outcome.receipt;
      expect(receipt.amountMinor, 376000); // never the 24 products
      expect(receipt.transactionDate, DateTime(2026, 11, 4)); // today
      expect(receipt.toCheck, [ScanCheck.dateNotRead, ScanCheck.amountUnsure]);
      expect(receipt.checkDate, isTrue);
      expect(receipt.checkAmount, isTrue);
      expect(outcome.dateFound, isFalse);
      expect(outcome.amountFound, isFalse);
      expect(outcome.readNote, contains('hard to read'));

      // Still flagged when the receipt is opened again later.
      receipt = (await receipts.getById(receipt.id))!;
      expect(receipt.toCheck, [ScanCheck.dateNotRead, ScanCheck.amountUnsure]);

      // An edit elsewhere (trip, translation) does not clear it.
      receipt = await commands().saveDetails(receipt.copyWith(description: 'x'));
      expect(receipt.toCheck, hasLength(2));

      // Counted at export, so unchecked values do not slip into file names.
      final export = ExportService(
        receipts: receipts,
        trips: trips,
        packages: packages,
        storage: storage,
        clock: clock,
      );
      expect((await export.export(const UnassignedScope())).toCheckCount, 1);

      // The user corrects the date and saves: nothing left to check.
      receipt = await commands().saveDetails(receipt.copyWith(
        transactionDate: DateTime(2026, 7, 28),
        toCheck: const [],
      ));
      expect(receipt.toCheck, isEmpty);
      expect((await receipts.getById(receipt.id))!.toCheck, isEmpty);
      expect((await export.export(const UnassignedScope())).toCheckCount, 0);
    });

    test('date read from the ticket number is used but flagged', () async {
      ocr.enqueueRows(misread({'28/07/2026 14:42': null}));
      final receipt = (await capturer()(photo('ticket.jpg').path)).receipt;
      expect(receipt.transactionDate, DateTime(2026, 7, 28));
      expect(receipt.amountMinor, 376000);
      expect(receipt.toCheck, [ScanCheck.dateUnsure]);
    });

    test('nothing read at all: both flagged', () async {
      final receipt = (await capturer()(photo('blank.jpg').path)).receipt;
      expect(receipt.toCheck, [ScanCheck.dateNotRead, ScanCheck.amountNotRead]);

      // Export reports the missing amount and, separately, the unchecked
      // date the file name carries.
      final result = await ExportService(
        receipts: receipts,
        trips: trips,
        packages: packages,
        storage: storage,
        clock: clock,
      ).export(const UnassignedScope());
      expect(result.missingAmountCount, 1);
      expect(result.toCheckCount, 1);
    });
  });

  group('trimming the photo to the receipt', () {
    List<OcrLine> block() => [
          for (var i = 0; i < 12; i++)
            OcrLine(
              text: 'LINE $i 10.00',
              left: 400,
              top: 600.0 + i * 60,
              right: 1000,
              bottom: 640.0 + i * 60,
            ),
        ];
    CaptureReceiptUseCase capturer(ImageProcessor images) =>
        CaptureReceiptUseCase(
          receipts: receipts,
          trips: trips,
          settings: settings,
          storage: storage,
          ocr: ocr,
          translation: FakeTranslation(),
          packages: packageService,
          idGenerator: nextId,
          imageProcessor: images,
          clock: clock,
        );
    File photo(String name) =>
        File(p.join(temp.path, name))..writeAsBytesSync([1, 2, 3]);

    test('paper not found (white on white): trimmed round the text', () async {
      final images = FakeImageProcessor(paperFound: false);
      ocr.queue.add(OcrResult(text: 'x', lines: block()));
      await capturer(images)(photo('white.jpg').path);
      expect(images.trims, hasLength(1));
      final text = images.trims.single;
      expect(text.box.left, 400);
      expect(text.box.right, 1000);
      expect(text.box.top, 600);
      expect(text.box.bottom, 600.0 + 11 * 60 + 40);
      expect(text.lineHeight, 40);
    });

    test('paper found: left as trimmed to the paper', () async {
      final images = FakeImageProcessor(paperFound: true);
      ocr.queue.add(OcrResult(text: 'x', lines: block()));
      await capturer(images)(photo('dark.jpg').path);
      expect(images.trims, isEmpty);
    });

    test('too little text to trust: not trimmed', () async {
      final images = FakeImageProcessor(paperFound: false);
      ocr.queue.add(OcrResult(text: 'x', lines: block().take(3).toList()));
      await capturer(images)(photo('sparse.jpg').path);
      expect(images.trims, isEmpty);
    });
  });

  test('upgrading an existing database keeps its receipts', () async {
    // A database as version 3 of the app left it.
    final path = p.join(temp.path, 'old.db');
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          for (var v = 1; v <= 3; v++) {
            for (final sql in Migrations.steps[v]!) {
              await db.execute(sql);
            }
          }
        },
      ),
    );
    await old.insert('receipts', {
      'id': 'old-1',
      'merchant': 'El Fogon',
      'transaction_date': '2026-11-04',
      'amount_minor': 42850,
      'currency': 'MXN',
      'country': 'Mexico',
      'claim_type': 'expense',
      'translation_status': 'pending',
      'status': 'needsClassification',
      'original_image_path': 'Standalone_Expenses/x/original_receipt.jpg',
      'captured_at': '2026-11-04T20:40:00.000Z',
      'updated_at': '2026-11-04T20:40:00.000Z',
    });
    await old.close();

    final upgraded =
        await AppDatabase.open(path: path, factory: databaseFactoryFfi);
    final repo = SqliteReceiptRepository(upgraded.db);
    final receipt = (await repo.getById('old-1'))!;
    expect(receipt.amountMinor, 42850);
    expect(receipt.toCheck, isEmpty); // nothing was flagged before
    await repo.upsert(receipt.copyWith(toCheck: const [ScanCheck.dateUnsure]));
    expect((await repo.getById('old-1'))!.toCheck, [ScanCheck.dateUnsure]);
    await upgraded.close();
  });

  test('a trip added afterwards picks up the receipts from its dates',
      () async {
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    File photo(String name) =>
        File(p.join(temp.path, name))..writeAsBytesSync([1, 2, 3]);
    // Scanned with no trip: 04/11 (El Fogon) and 28/07 (the restaurant bill).
    ocr
      ..enqueueRows(elFogonRows)
      ..enqueueRows(misread({}));
    final fogon = (await capture(photo('a.jpg').path)).receipt;
    final bill = (await capture(photo('b.jpg').path)).receipt;
    expect(fogon.tripId, isNull);
    expect(bill.tripId, isNull);

    final tripCommands = TripCommands(
      trips: trips,
      receipts: receipts,
      settings: settings,
      packageService: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    final trip = await tripCommands.create(
      name: 'Workshop',
      country: 'Venezuela',
      startDate: DateTime(2026, 11, 2),
      endDate: DateTime(2026, 11, 6),
    );
    expect((await tripCommands.looseReceipts()).map((r) => r.id).toSet(),
        {fogon.id, bill.id});
    final offered = await tripCommands.looseReceiptsFor(trip);
    expect(offered.map((r) => r.id), [fogon.id]);

    await tripCommands.assignReceipts(trip, offered);
    final moved = (await receipts.getById(fogon.id))!;
    expect(moved.tripId, trip.id);
    expect(moved.country, 'Venezuela'); // takes the trip's country
    expect(moved.originalImagePath, startsWith('Trips/Workshop_2026/'));
    expect((await receipts.getById(bill.id))!.tripId, isNull);
    expect(await tripCommands.looseReceiptsFor(trip), isEmpty);
  });

  test('automatic translation reuses the page scan, not a second read of the '
      'small crop', () async {
    final capture = CaptureReceiptUseCase(
      receipts: receipts,
      trips: trips,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translation: FakeTranslation(),
      packages: packageService,
      idGenerator: nextId,
      clock: clock,
    );
    ocr.enqueueRows(elFogonRows);
    final receipt = (await capture(
            (File(p.join(temp.path, 'sb.jpg'))..writeAsBytesSync([1, 2, 3])).path))
        .receipt;

    OcrLine line(String text, double left, double right, double top) =>
        OcrLine(text: text, left: left, top: top, right: right, bottom: top + 24);
    // First read, of the whole page: right. Second read, of the crop: the
    // damaged text the phone gave for a small strip.
    ocr.queue
      ..add(OcrResult(text: '', lines: [
        line('Starbucks Coffee Emerson', 100, 500, 40),
        line('Lobby', 80, 200, 100),
        line('1 VT Berry Pearls Lem', 60, 360, 140),
        line('114.00', 420, 500, 140),
        line('VT PQT-COMP Nitro', 100, 360, 170),
        line('1 GD Caramel F', 60, 300, 200),
        line('97.00', 440, 500, 200),
        line('GD L Entera F', 100, 300, 230),
        line('Total', 60, 160, 330),
        line('211.00', 420, 500, 330),
      ]))
      ..add(OcrResult(text: '', lines: [
        line('1 VTBerry Pear ls Lem', 60, 360, 140),
        line('114.00', 420, 500, 140),
        line('1 GO Caraael F', 60, 300, 200),
        line('97.00', 440, 500, 200),
      ]));
    final draft = await TranslateItemsUseCase(
      receipts: receipts,
      translations: translations,
      packages: packages,
      packageService: packageService,
      settings: settings,
      storage: storage,
      ocr: ocr,
      translator: FakeTranslation(),
      imageProcessor: FakeImageProcessor(paperFound: true),
      clock: clock,
    ).prepareAutomatically(receipt: receipt);
    expect(draft, isNotNull);
    expect(draft!.lines.map((l) => l.originalText).toList(),
        // The options printed under each drink come with it.
        ['VT Berry Pearls Lem', 'VT PQT-COMP Nitro', 'GD Caramel F', 'GD L Entera F']);
    expect(ocr.queue, hasLength(1)); // the crop was never read again
  });
}

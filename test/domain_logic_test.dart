import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/entities/receipt.dart';
import 'package:expense_assistant/domain/entities/translation_line.dart';
import 'package:expense_assistant/domain/logic/claim_documents.dart';
import 'package:expense_assistant/domain/reference/countries.dart';
import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/meal_type_guesser.dart';
import 'package:expense_assistant/domain/logic/ocr_row_assembler.dart';
import 'package:expense_assistant/domain/logic/package_naming.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:expense_assistant/domain/logic/text_normaliser.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:expense_assistant/domain/value_objects/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// A typical Mexico City restaurant ticket, as OCR rows.
const elFogonRows = [
  'EL FOGON',
  'OPERADORA FOGON S.A. DE C.V.',
  'RFC: OFO123456AB1',
  'AV. REFORMA 350, COL. JUAREZ',
  'CDMX C.P. 06600',
  'FECHA: 04/11/2026  HORA: 14:35',
  'MESA: 12  MESERO: JUAN',
  '4 TACOS AL PASTOR      220.00',
  '2 AGUA MINERAL          70.00',
  '2 CAFE AMERICANO        79.40',
  'SUBTOTAL               369.40',
  'IVA 16%                 59.10',
  'TOTAL                 \$428.50',
  'PROPINA SUGERIDA 10%    42.85',
  'EFECTIVO               500.00',
  'CAMBIO                  71.50',
  'GRACIAS POR SU VISITA',
];

Receipt sampleReceipt({TranslationStatus translation = TranslationStatus.complete}) =>
    Receipt(
      id: 'r1',
      merchant: 'El Fogon',
      transactionDate: DateTime(2026, 11, 4),
      amountMinor: 42850,
      currency: 'MXN',
      country: 'Mexico',
      claimType: ClaimType.expense,
      category: 'Meals Overseas',
      mealType: MealType.lunch,
      description: 'Lunch whilst attending ACS workshop',
      detectedLanguage: 'es',
      translationStatus: translation,
      originalImagePath:
          'Standalone_Expenses/2026-11-04_ElFogon_428.50MXN/original_receipt.jpg',
      capturedAt: DateTime.utc(2026, 11, 4, 20, 40),
      updatedAt: DateTime.utc(2026, 11, 4, 20, 41),
    );

void main() {
  group('Money.parseMinor', () {
    test('handles decimal point and comma conventions', () {
      expect(Money.parseMinor('428.50'), 42850);
      expect(Money.parseMinor('428,50'), 42850);
      expect(Money.parseMinor(r'$1,234.50'), 123450);
      expect(Money.parseMinor('1.234,50'), 123450);
      expect(Money.parseMinor('1,234'), 123400);
      expect(Money.parseMinor('12,5'), 1250);
      expect(Money.parseMinor('MXN 90'), 9000);
      expect(Money.parseMinor('(12.00)'), -1200);
      expect(Money.parseMinor('abc'), isNull);
    });

    test('respects currency exponent', () {
      expect(Money.parseMinor('1.500', exponent: 0), 1500); // CLP thousands
      expect(Money.parseMinor('1.250', exponent: 3), 1250); // KWD decimals
      expect(Money.parseMinor('10.0051', exponent: 2), 1001); // rounds half up
    });

    test('formats without grouping', () {
      expect(const Money(42850, 'MXN').amountText, '428.50');
      expect(const Money(1500, 'JPY').amountText, '1500');
      expect(const Money(5, 'GBP').amountText, '0.05');
      expect(const Money(42850, 'MXN').toString(), '428.50 MXN');
    });
  });

  group('ReceiptTextParser', () {
    DateTime clock() => DateTime(2026, 11, 4, 15);

    test('reads a Mexican restaurant ticket', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parseRows(elFogonRows);
      expect(parsed.merchant, 'El Fogon');
      expect(parsed.date, DateTime(2026, 11, 4));
      expect(parsed.time, '14:35');
      expect(parsed.amountMinor, 42850); // not subtotal, tip, cash or change
      expect(parsed.currency, 'MXN');
    });

    test('names the app, not the rider, on an Uber receipt', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parseRows([
        'Uber One',
        '4 Nov 2026, 13:23',
        'Thanks for riding,',
        'Juan',
        'Total MX\$47.86',
        'Trip fare MX\$51.62',
        'Booking fee MX\$8.31',
        'Uber One credits -MX\$12.07',
      ]);
      expect(parsed.merchant, 'Uber');
      expect(parsed.amountMinor, 4786);
    });

    test('skips the customer name after a greeting', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parseRows(['Gracias por tu compra,', 'Juan', 'LA PARRILLA', 'TOTAL 10.00']);
      expect(parsed.merchant, 'La Parrilla');
    });

    test('prefers the total including tip', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parseRows([
        'CAFE LA ESQUINA',
        '4 de noviembre de 2026',
        'TOTAL 428.50',
        'PROPINA 42.85',
        'TOTAL CON PROPINA 471.35',
      ]);
      expect(parsed.date, DateTime(2026, 11, 4));
      expect(parsed.amountMinor, 47135);
      expect(parsed.merchant, 'Cafe la Esquina');
    });

    test('reads a US receipt with month-first dates and ISO currency', () {
      final parsed = ReceiptTextParser(
        defaultCurrency: 'USD',
        monthFirstDates: true,
        clock: clock,
      ).parseRows([
        'STARBUCKS COFFEE',
        'Store 1234',
        '11/03/2026 08:12 AM',
        'Grande Latte 5.25',
        'Croissant 3.95',
        'Subtotal 9.20',
        'Tax 0.76',
        'Total USD 9.96',
        'VISA ************1234',
      ]);
      expect(parsed.merchant, 'Starbucks Coffee');
      expect(parsed.date, DateTime(2026, 11, 3));
      expect(parsed.time, '08:12');
      expect(parsed.amountMinor, 996);
      expect(parsed.currency, 'USD');
      expect(parsed.currencyDetected, isTrue);
    });

    test('ignores impossible and future dates', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parseRows(['SHOP', '31/02/2026', '01/12/2027', '03-11-2026', 'TOTAL 10.00']);
      expect(parsed.date, DateTime(2026, 11, 3));
    });

    test('uses OCR geometry to rebuild rows', () {
      final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
          .parse(const OcrResult(text: '', lines: [
        OcrLine(text: 'TOTAL', left: 10, top: 500, right: 80, bottom: 520),
        OcrLine(text: 'EL FOGON', left: 50, top: 10, right: 250, bottom: 50),
        OcrLine(text: r'$428.50', left: 300, top: 502, right: 380, bottom: 521),
      ]));
      expect(parsed.merchant, 'El Fogon');
      expect(parsed.amountMinor, 42850);
    });
  });

  group('OcrRowAssembler', () {
    test('joins items and prices that ML Kit returned in separate blocks', () {
      final rows = OcrRowAssembler.assemble(const [
        OcrLine(text: 'TACOS AL PASTOR', left: 10, top: 100, right: 200, bottom: 120),
        OcrLine(text: 'AGUA MINERAL', left: 10, top: 130, right: 180, bottom: 150),
        OcrLine(text: '220.00', left: 300, top: 102, right: 360, bottom: 121),
        OcrLine(text: '70.00', left: 300, top: 131, right: 350, bottom: 150),
      ]);
      expect(rows.map((r) => r.text).toList(), [
        'TACOS AL PASTOR  220.00',
        'AGUA MINERAL  70.00',
      ]);
    });
  });

  group('ItemLineParser', () {
    test('splits quantity, description and amount', () {
      final item = ItemLineParser.parse('4 TACOS AL PASTOR      220.00')!;
      expect(item.quantity, '4');
      expect(item.description, 'TACOS AL PASTOR');
      expect(item.amountText, '220.00');

      final coffee = ItemLineParser.parse('2x Café de olla 60.00')!;
      expect(coffee.quantity, '2');
      expect(coffee.description, 'Café de olla');

      final water = ItemLineParser.parse(r'AGUA MINERAL $35.00')!;
      expect(water.quantity, isNull);
      expect(water.amountText, '35.00');
    });

    test('drops totals, tax, tips and card lines', () {
      for (final row in [
        'SUBTOTAL 369.40',
        'IVA 16% 59.10',
        'TOTAL 428.50',
        'PROPINA 42.85',
        'VISA ************1234',
        '----------',
        '220.00',
      ]) {
        expect(ItemLineParser.parse(row), isNull, reason: row);
      }
    });
  });

  group('PackageNaming', () {
    test('builds the package folder name from the brief', () {
      expect(
        PackageNaming.receiptFolder(
          date: DateTime(2026, 11, 4),
          merchant: 'El Fogón',
          amountMinor: 42850,
          currency: 'MXN',
        ),
        '2026-11-04_ElFogon_428.50MXN',
      );
      expect(
        PackageNaming.receiptFolder(
          date: DateTime(2026, 11, 4),
          merchant: 'EL FOGON DE LA CONDESA',
          amountMinor: 150000,
          currency: 'JPY',
        ),
        '2026-11-04_ElFogonDeLaCondesa_150000JPY',
      );
      expect(
        PackageNaming.receiptFolder(currency: 'MXN'),
        'undated_UnknownMerchant_NoAmountMXN',
      );
    });

    test('trip folder and export names', () {
      expect(PackageNaming.tripFolder('Caracas ACS Workshop', DateTime(2026, 11, 9)),
          'Caracas_ACS_Workshop_2026');
      expect(PackageNaming.tripExportName('Caracas Workshop', DateTime(2026, 11, 9)),
          'Caracas_Workshop_Nov_2026');
      expect(
          PackageNaming.tripExportName('Caracas Workshop 2026', DateTime(2026, 11, 9)),
          'Caracas_Workshop_Nov_2026');
      expect(
        PackageNaming.receiptFileBase(
            currency: 'MXN', date: DateTime(2026, 11, 4), amountMinor: 42850),
        '2026-11-04_428.50MXN',
      );
      expect(
        PackageNaming.receiptFileBase(
            currency: 'MXN', date: DateTime(2026, 11, 4)),
        '2026-11-04_NoAmountMXN',
      );
      expect(
        PackageNaming.tripZipName(
            'Caracas ACS Workshop', DateTime(2026, 11, 9), DateTime(2026, 1, 1)),
        'Caracas_ACS_Workshop_2026-11-09',
      );
      expect(
        PackageNaming.tripZipName('Accra', null, DateTime(2026, 1, 2)),
        'Accra_2026-01-02',
      );
      expect(PackageNaming.unique('a', {'a', 'a_2'}), 'a_3');
    });
  });

  group('ClaimDocuments', () {
    test('claim summary matches the brief, ready to paste into Oracle', () {
      final summary = ClaimDocuments.claimSummary(
        receipt: sampleReceipt(),
        attachments: ['original_receipt.jpg', 'translated_items.pdf'],
      );
      expect(
        summary,
        'CLAIM SUMMARY\n'
        '\n'
        'Merchant:\nEl Fogon\n\n'
        'Date:\n04 Nov 2026\n\n'
        'Amount:\n428.50 MXN\n\n'
        'Claim Type:\nExpense Claim\n\n'
        'Category:\nMeals Overseas\n\n'
        'Meal Type:\nLunch\n\n'
        'Location:\nMexico\n\n'
        'Description:\nLunch whilst attending ACS workshop\n\n'
        'Attachments:\n'
        'original_receipt.jpg\n'
        'translated_items.pdf\n',
      );
    });

    test('metadata uses the brief schema keys', () {
      final meta = ClaimDocuments.metadata(
        receipt: sampleReceipt(),
        attachments: ['original_receipt.jpg'],
        generatedAt: DateTime.utc(2026, 11, 4, 21),
      );
      expect(meta['claimType'], 'Expense Claim');
      expect(meta['category'], 'Meals Overseas');
      expect(meta['mealType'], 'Lunch');
      expect(meta['merchant'], 'El Fogon');
      expect(meta['country'], 'Mexico');
      expect(meta['amount'], '428.50');
      expect(meta['currency'], 'MXN');
      expect(meta['date'], '2026-11-04');
      expect(meta['description'], 'Lunch whilst attending ACS workshop');
      expect(meta['status'], 'ready');
    });

    test('translation text lists original and English', () {
      final text = ClaimDocuments.translatedItemsText(
        receipt: sampleReceipt(),
        lines: const [
          TranslationLine(
            lineNo: 1,
            quantity: '4',
            originalText: 'TACOS AL PASTOR',
            translatedText: 'Pork tacos (al pastor)',
            amountText: '220.00',
            sourceLanguage: 'es',
            engine: TranslationEngine.glossary,
          ),
        ],
      );
      expect(text, contains('FOOD'));
      expect(text, contains('TACOS AL PASTOR'));
      expect(text, isNot(contains('220.00')));
      expect(text, contains('  = Pork tacos (al pastor)'));
      expect(text, contains('Translation: Spanish to English'));
    });
  });

  group('Receipt status', () {
    test('moves through the workflow', () {
      final draft = sampleReceipt(translation: TranslationStatus.pending)
          .copyWith(description: null);
      expect(draft.status, ReceiptStatus.needsClassification);
      expect(draft.missingFields, ['description']);
      final classified = draft.copyWith(description: 'Lunch');
      expect(classified.status, ReceiptStatus.needsTranslation);
      final translated =
          classified.copyWith(translationStatus: TranslationStatus.complete);
      expect(translated.status, ReceiptStatus.ready);
      expect(translated.copyWith(submittedAt: DateTime(2026, 11, 30)).status,
          ReceiptStatus.submitted);
    });

    test('meal type only required for meal categories', () {
      final taxi = sampleReceipt()
          .copyWith(category: 'Travel Overseas Taxi', mealType: null);
      expect(taxi.isClassified, isTrue);
      final meal = sampleReceipt().copyWith(mealType: null);
      expect(meal.missingFields, ['meal type']);
    });
  });

  test('meal type guess and glossary key', () {
    expect(MealTypeGuesser.fromTimeString('08:12'), MealType.breakfast);
    expect(MealTypeGuesser.fromTimeString('14:35'), MealType.lunch);
    expect(MealTypeGuesser.fromTimeString('20:05'), MealType.dinner);
    expect(MealType.fromName('refreshments'), MealType.refreshments);
    expect(MealType.refreshments.label, 'Refreshments');
    expect(TextNormaliser.glossaryKey('Café  Americano.'), 'cafe americano');
  });

  test('country is detected from receipt text', () {
    expect(
      Countries.detectInText('C.EJEMPLO, COL. CENTRO\nSAN SALVADOR, SAN SALVADOR.'),
      'El Salvador',
    );
    expect(Countries.detectInText('CDMX C.P. 06600'), 'Mexico');
    expect(Countries.detectInText('Santa Fe, New Mexico'), isNull);
    expect(Countries.detectInText('CHILE RELLENO 90.00\nTURKEY CLUB'), isNull);
    expect(Countries.detectInText(''), isNull);
  });
}

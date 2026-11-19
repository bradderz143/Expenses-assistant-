import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// the restaurant bill, Mexico City, 28/07/2026: 3,760.00 pesos. Scanned from a
/// faint, curled photo, the app showed 24.00 (the "Total de productos"
/// count) and the day of the scan. These are the rows as printed.
const sampleBillRows = [
  'RESTAURANTE EJEMPLO CENTRO',
  'ALIMENTOS EJEMPLO SA DE CV',
  'CALLE EJEMPLO 100 COL CENTRO CDMX 06000',
  'RFC: XXX010101AB1',
  'AV EJEMPLO 2 LOC 1 CENTRO 06000',
  'MESA: T11A  #EST: 73 FOLIO: 100001',
  '# PER: 6  JUAN PEREZ LOPEZ',
  '28/07/2026 14:42',
  'CANT  DESCRIPCION  IMPORTE',
  r'3  Salmon S/Mango @$390.  $1,170.00',
  r'1  F Res Sal Q/Cab @$390  $390.00',
  r'1  Pechu Mol Verde @$280  $280.00',
  r'1  Lengua al Gusto @$395  $395.00',
  'Veracruz',
  r'3  Agua Topo Chico @$72.  $216.00',
  r'1  Naranjada @$59.00  $59.00',
  r'1  Naranjada @$59.00  $59.00',
  r'1  Limonada @$59.00  $59.00',
  r'1  Clamato Natural @$85.  $85.00',
  r'5  Cuervo Reposado @$110  $550.00',
  r'1  Pastel 3 Leches @$140  $140.00',
  r'1  Mousse Guanaban @$110  $110.00',
  r'1  Espres Dob Regu @$82.  $82.00',
  r'1  Espres Regular @$55.0  $55.00',
  r'1  Cafe de Olla @$55.00  $55.00',
  r'1  Cafe de Olla @$55.00  $55.00',
  r'Total  $3,760.00',
  '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)',
  'Total de productos : 24',
  'FACTURACION TICKETS DEL MES, DEL DIA',
  'DE CONSUMO Y HASTA LAS 19 HRS DEL ULTIMO',
  'DIA DEL MES.',
  '*** FACTURACION ***',
  'Obtenga su factura en:',
  'https://www.ejemplo.com/fe/index.aspx',
  'Proporcionando los datos:',
  'Tienda: 5',
  'Ticket: 20260728-001-100001-00001',
  '*** ACLARACIONES ***',
  'SOLICITUD DE FACTURAS DE MESES',
  'ANTERIORES Y PROBLEMAS',
  'facturacion@ejemplo.com',
];

const _total = r'Total  $3,760.00';
const _words = '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)';
const _count = 'Total de productos : 24';
const _date = '28/07/2026 14:42';
const _ticket = 'Ticket: 20260728-001-100001-00001';

/// The receipt with some rows misread (a new string) or lost (null).
List<String> misread(Map<String, String?> changes) => [
      for (final row in sampleBillRows)
        if (!changes.containsKey(row))
          row
        else if (changes[row] != null)
          changes[row]!,
    ];

void main() {
  DateTime clock() => DateTime(2026, 11, 13, 22, 52);
  ParsedReceipt parse(List<String> rows) =>
      ReceiptTextParser(defaultCurrency: 'MXN', clock: clock).parseRows(rows);

  test('read cleanly: the total, not the product count', () {
    final parsed = parse(sampleBillRows);
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
    expect(parsed.date, DateTime(2026, 7, 28));
    expect(parsed.dateDoubtful, isFalse);
    expect(parsed.time, '14:42');
    expect(parsed.merchant, 'Restaurante Ejemplo Centro');
  });

  group('the product count is never the amount', () {
    // However OCR spells it, with the real total row unreadable.
    for (final count in [
      'Total de productos : 24',
      'Total de productcs : 24',
      'Total de pr0ductos: 24',
      'Total de proouctos : 24',
      'Tota1 de productos : 24',
      'TOTAL PRODUCTOS 24',
      'Total de productos :  24  ',
      'Total de articulos : 24',
    ]) {
      test(count, () {
        final parsed = parse(misread({
          _total: 'Tota1  S3,76O.OO',
          _words: '(**IRES MIL SEIECIENIOS SESENTA PESOS OO/1OO **)',
          _count: count,
        }));
        // Nothing states the total any more, so the items are added up and
        // the user is asked to check.
        expect(parsed.amountMinor, 376000);
        expect(parsed.amountDoubtful, isTrue);
      });
    }
  });

  test('the count wins nothing even when it is the only "total" left', () {
    final parsed = parse(misread({
      _total: null,
      _words: null,
      _count: 'Total de proouctos : 24',
      for (final row in sampleBillRows)
        if (row.contains(r'@$')) row: null,
    }));
    // No prices at all were read: better no amount than 24.00 unflagged.
    expect(parsed.amountMinor == 2400 && !parsed.amountDoubtful, isFalse);
  });

  test('total row unreadable: the amount in words and the items agree', () {
    final parsed = parse(misread({_total: 'Tota1  S3,76O.OO'}));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test(r'$ read as 5: the words and the items overrule 53,760.00', () {
    final parsed = parse(misread({_total: 'Total  53,760.00'}));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test(r'$ read as 5 or 8 on the total and on items, no words', () {
    final parsed = parse(misread({
      _total: 'lotal  83,760.00',
      _words: null,
      r'1  Naranjada @$59.00  $59.00': r'1  Naranjada @$59.00  559.00',
      r'1  Clamato Natural @$85.  $85.00': r'1  Clamato Natural @$85.  885.00',
      r'1  F Res Sal Q/Cab @$390  $390.00': r'1  F Res Sal Q/Cab @$390  8390.00',
    }));
    // One Naranjada at 59.00 is 59.00, not 559.00; the last row then equals
    // the sum of the items once its 8 is read as the sign too.
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('zeros read as the letter O in the prices', () {
    final parsed = parse(misread({
      _total: r'Total $3,76o.oO',
      _words: null,
      r'1  Pastel 3 Leches @$140  $140.00': r'1  Pastel 3 Leches @$14O  $140.OO',
      r'1  F Res Sal Q/Cab @$390  $390.00': r'1  F Res Sal Q/Cab @$39O  $39O.00',
    }));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('the total printed beside the last item, the count beside "Total"', () {
    final rows = [
      for (final row in sampleBillRows)
        if (row == _total)
          'Total  24'
        else if (row == _words)
          ...<String>[]
        else if (row == _count)
          'Total de productos :'
        else
          row,
    ];
    final last = rows.lastIndexOf(r'1  Cafe de Olla @$55.00  $55.00');
    rows[last] = r'1  Cafe de Olla @$55.00  $3,760.00  $55.00';
    final parsed = parse(rows);
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('a later, larger total after the words is the bill plus the tip', () {
    final parsed = parse([
      'LA PARRILLA',
      'FECHA 12/11/2026',
      '2 ARRACHERA 300.00',
      '2 CERVEZA 128.50',
      'TOTAL 428.50',
      '(CUATROCIENTOS VEINTIOCHO PESOS 50/100 M.N.)',
      'PROPINA 42.85',
      'TOTAL 471.35',
    ]);
    expect(parsed.amountMinor, 47135);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('a digit of the total misread: the words and the items overrule it',
      () {
    final parsed = parse(misread({_total: r'Total  $3,780.00'}));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('"Total" misread and no words: the row that sums the items is it', () {
    final parsed = parse(misread({_total: r'lotal  $3,760.00', _words: null}));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('total on the row under its label', () {
    final rows = [
      for (final row in sampleBillRows)
        if (row == _total) ...['Total', r'$3,760.00'] else row,
    ];
    final parsed = parse(rows);
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('a misread item price: the total still stands, backed by the words',
      () {
    final parsed = parse(misread({
      r'5  Cuervo Reposado @$110  $550.00': r'5  Cuervo Reposado @$110  $580.00',
    }));
    expect(parsed.amountMinor, 376000);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('total disagrees with the items and no words: flagged', () {
    final parsed = parse(misread({
      _total: r'Total  $3,780.00',
      _words: null,
    }));
    expect(parsed.amountMinor, 378000);
    expect(parsed.amountDoubtful, isTrue);
  });

  group('date', () {
    test('month digit lost: the ticket number has it, and the day and year '
        'that survive agree', () {
      for (final damaged in [
        "28/0'/2026 14:42",
        '28/0//2026 14:42',
        '28/0 /2026 14:42',
        '28//2026 14:42',
      ]) {
        final parsed = parse(misread({_date: damaged}));
        expect(parsed.date, DateTime(2026, 7, 28), reason: damaged);
        expect(parsed.dateDoubtful, isFalse, reason: damaged);
      }
    });

    test('date row lost: the ticket number alone is used, to be checked', () {
      for (final ticket in [_ticket, 'Ticket: 2O26O728-001-100001-00001']) {
        final parsed = parse(misread({_date: null, _ticket: ticket}));
        expect(parsed.date, DateTime(2026, 7, 28), reason: ticket);
        expect(parsed.dateDoubtful, isTrue, reason: ticket);
      }
      // What survives of the printed date contradicts the ticket number.
      final parsed = parse(misread({_date: "12/0'/2026 14:42"}));
      expect(parsed.date, DateTime(2026, 7, 28));
      expect(parsed.dateDoubtful, isTrue);
    });

    test('a phone number is not a date', () {
      final parsed = parse(misread({
        _date: null,
        _ticket: 'Tel: 20230115',
      }));
      expect(parsed.date, isNull);
    });

    test('letters for digits and stray spaces are repaired', () {
      for (final noisy in [
        '28/O7/2026 14:42',
        '28/07/2O26 14:42',
        '2B/07/2026 14:42',
        '28 / 07 / 2026 14:42',
        '28/07 /2026 14:42',
        '28/07/202614:42',
        'JUAN PEREZ LOPEZ28/07/2026',
      ]) {
        final parsed = parse(misread({_date: noisy}));
        expect(parsed.date, DateTime(2026, 7, 28), reason: noisy);
        expect(parsed.dateDoubtful, isFalse, reason: noisy);
      }
    });

    test('unreadable and no ticket number: no date, never a guess', () {
      final parsed = parse(misread({_date: "28/0'/2026 14:42", _ticket: null}));
      expect(parsed.date, isNull);
    });

    test('printed date and ticket number disagree: flagged', () {
      final parsed = parse(misread({_date: '28/01/2026 14:42'}));
      expect(parsed.date, DateTime(2026, 1, 28));
      expect(parsed.dateDoubtful, isTrue);
    });

    test('a date more than a year old is flagged', () {
      final parsed = parse(misread({_date: '28/07/2020 14:42', _ticket: null}));
      expect(parsed.date, DateTime(2020, 7, 28));
      expect(parsed.dateDoubtful, isTrue);
    });
  });
}

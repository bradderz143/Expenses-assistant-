import 'package:expense_assistant/domain/logic/amount_in_words.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scan_misread_test.dart' show misread;

/// Receipts found by reviewing the scan fix, each read wrongly (or flagged
/// for no reason) by an earlier version of it.
void main() {
  DateTime clock() => DateTime(2026, 11, 13, 18);
  ParsedReceipt parse(
    List<String> rows, {
    String currency = 'MXN',
    bool monthFirst = false,
  }) =>
      ReceiptTextParser(
        defaultCurrency: currency,
        monthFirstDates: monthFirst,
        clock: clock,
      ).parseRows(rows);

  void expectAmount(ParsedReceipt p, int minor, {bool flagged = false}) {
    expect(p.amountMinor, minor);
    expect(p.amountDoubtful, flagged);
  }

  group('amount', () {
    test('total with tip kept when both "TOTAL" labels are misread', () {
      expectAmount(
        parse([
          'LA POLAR',
          '09/11/2026 15:00',
          r'2 BIRRIA $360.00',
          r'2 CERVEZA $140.00',
          r'1 FLAN $65.00',
          r'T0TAL $565.00',
          r'PROPINA $85.00',
          r'T0TAL CON PROPINA $650.00',
        ]),
        65000,
      );
      expectAmount(
        parse([
          'OLIVE GARDEN',
          '11/10/2026',
          'Lasagna 18.99',
          'Chicken Alfredo 20.49',
          'Soda 3.29',
          'T0tal 42.77',
          'Tip 8.00',
          'T0tal incl. tip 50.77',
        ], currency: 'USD', monthFirst: true),
        5077,
      );
      expectAmount(
        parse([
          'DINER',
          '11/10/2026',
          'Burger 12.00',
          'Fries 4.00',
          'Total 16.00',
          'Tip 3.00',
          'Total with tip 19.00',
        ], currency: 'USD', monthFirst: true),
        1900,
      );
    });

    test('subtotal + tax still overrules an item and total misread alike', () {
      // A faded 0 read as 8 in one item and in the total: 528/818 for 520/810.
      expectAmount(
        parse([
          'LA CASA DE TONO',
          'MESA 12 PERSONAS 4',
          '12/11/2026 21:15',
          r'4 POZOLE GDE $528.00',
          r'4 TOSTADA $160.00',
          r'2 REFRESCO $70.00',
          r'2 AGUA $60.00',
          r'SUBTOTAL $698.28',
          r'IVA $111.72',
          r'TOTAL $818.00',
          r'PROPINA SUGERIDA 15% $121.50',
        ]),
        81000,
        flagged: true,
      );
      // And the card payment agrees with subtotal + tax.
      expectAmount(
        parse([
          'STARBUCKS',
          '12/11/2026 08:15',
          r'1 LATTE GDE $79.80',
          r'1 CROISSANT $52.00',
          r'SUBTOTAL $112.93',
          r'IVA 16% $18.07',
          r'TOTAL $131.80',
          r'VISA $131.00',
        ]),
        13100,
      );
    });

    test('a tip, service charge or room service is not a misread', () {
      expectAmount(
        parse([
          'THE IVY',
          '10/11/2026 20:10',
          '2 Fish & Chips 36.00',
          '1 Burger 16.00',
          '2 Glass Wine 18.00',
          '1 Sticky Toffee 10.00',
          'Service charge 12.5% 10.00',
          'Total 90.00',
        ], currency: 'GBP'),
        9000,
      );
      expectAmount(
        parse([
          'LA POLAR',
          '09/11/2026 15:00',
          '2 BIRRIA 360.00',
          '2 CERVEZA 140.00',
          'SUBTOTAL 500.00',
          'PROPINA 50.00',
          'TOTAL 550.00',
        ]),
        55000,
      );
      expectAmount(
        parse([
          'BLUE DINER',
          '11/10/2026 12:30',
          'Pancakes 14.00',
          'Coffee 6.00',
          'Tip 3.60',
          'Total 23.60',
        ], currency: 'USD', monthFirst: true),
        2360,
      );
      expectAmount(
        parse([
          'HOTEL CAMINO REAL',
          'FOLIO 12345',
          'LLEGADA 10/11/2026',
          'HOSPEDAJE 2,500.00',
          'SERVICIO A CUARTO 350.00',
          'TOTAL 2,850.00',
        ]),
        285000,
      );
    });

    test('a discount with a percentage is taken off the items', () {
      expectAmount(
        parse([
          'FARMACIA',
          '12/11/2026',
          '1 ANALGESICO 200.00',
          '1 VITAMINAS 300.00',
          'DESCUENTO 10% -50.00',
          'TOTAL 450.00',
        ]),
        45000,
      );
    });

    test('a price per kilo is not an item', () {
      expectAmount(
        parse([
          'CHEDRAUI',
          '12/11/2026 11:00',
          'JAMON VIRGINIA',
          'PESO 0.350 KG',
          r'PRECIO/KG $189.00',
          r'TOTAL $66.15',
        ]),
        6615,
      );
    });

    test('dotted phone numbers and dates do not make whole pesos suspect', () {
      expectAmount(
        parse([
          'TAQUERIA LOS COCUYOS',
          'TEL. 55.12.34.56',
          'FECHA 13.11.26',
          r'4 TACOS SUADERO $80',
          r'2 REFRESCO $50',
          r'TOTAL $130',
        ]),
        13000,
      );
    });
  });

  group('amount in words', () {
    test('a phrase cut short by a damaged word is not read at all', () {
      for (final row in [
        'IMPORTE CON LETRA: TRES MIL SETECIENTOS SES#NTA PESOS 00/100 M.N.',
        'Amount in words: Three Thousand Seven Hundred and Sxty Naira Only',
        'SON: UN MIL C#ENTO SESENTA PESOS 00/100',
        'CANTIDAD CON LETRA: UN MIL SETENTA Y OCMO PESOS 00/100 M.N.',
      ]) {
        expect(AmountInWords.find([row]), isEmpty, reason: row);
      }
      // Labelled, but whatever followed is lost: it may only back a figure.
      final lost = AmountInWords.find([
        'IMPORTE CON LETRA: TRES MIL SETECIENTOS',
        'Total de productos : 24',
      ]);
      expect(lost.where((w) => w.formal), isEmpty);
      final rupees =
          AmountInWords.find(['Amount in words: Rupees One Thousand Four Hundred']);
      expect(rupees.where((w) => w.formal), isEmpty);
    });

    test('a stray space inside a number word', () {
      int? whole(String row) {
        final found = AmountInWords.find([row]);
        return found.isEmpty ? null : found.single.whole;
      }

      expect(whole('UN MIL NOVE NTA PESOS 00/100'), 1090);
      expect(whole('DOS MIL CIEN TO OCHENTA PESOS 00/100'), 2180);
      expect(whole('Two Hundred Six ty Dollars Only'), 260);
    });

    test('a cents marker glued to the words round it', () {
      for (final words in [
        '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100M.N.**)',
        '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100MN**)',
        '(**TRES MIL SETECIENTOS SESENTA PESOS00/100 **)',
      ]) {
        final found = AmountInWords.find([words]);
        expect(found.single.whole, 3760, reason: words);
        expect(found.single.formal, isTrue, reason: words);
        // So it still corrects a misread total, backed by the items.
        expectAmount(
          parse(misread({
            r'Total  $3,760.00': r'Total  $3,780.00',
            '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)': words,
          })),
          376000,
        );
        // With an item lost too, words and figures differ by a look-alike
        // digit and nothing settles it: the words' amount, to be checked.
        expectAmount(
          parse(misread({
            r'Total  $3,760.00': r'Total  $3,780.00',
            '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)': words,
            r'1  Limonada @$59.00  $59.00': r'1  Limonada @$59.00  $5',
          })),
          376000,
          flagged: true,
        );
      }
    });

    test('a damaged phrase never overrules a total that the receipt backs', () {
      expectAmount(
        parse([
          'HOTEL MISION RESTAURANTE',
          'PASEO DE LA REFORMA 250 CDMX',
          'FECHA 10/11/2026 14:05',
          '2 CHILAQUILES VERDES 380.00',
          '2 CAFE AMERICANO 130.00',
          '1 JUGO VERDE 95.00',
          '3 MOLLETES 375.00',
          'SUBTOTAL 844.83',
          'IVA 16% 135.17',
          'SERVICIO 10% 98.00',
          'TOTAL 1,078.00',
          'CANTIDAD CON LETRA: UN MIL SETENTA Y OCMO PESOS 00/100 M.N.',
        ]),
        107800,
      );
      expectAmount(
        parse([
          'THE ORIENTAL LAGOS',
          '12/11/2026',
          'Jollof Rice x2 6,000.00',
          'Suya Platter 7,000.00',
          'Sub Total 13,000.00',
          'VAT 7.5% 975.00',
          'Service Charge 10% 1,300.00',
          'TOTAL 15,275.00',
          'Amount in words: Fifteen Thousand Two Hundred and Seventy Fivc '
              'Naira Only',
        ], currency: 'NGN'),
        1527500,
      );
      expectAmount(
        parse([
          'SARAVANA BHAVAN',
          'Date: 12/11/2026',
          'Masala Dosa 700.00',
          'Thali 700.00',
          'Sub Total 1,400.00',
          'CGST @2.5% 35.00',
          'SGST @2.5% 35.00',
          'Grand Total 1,470.00',
          'Amount in words: Rupees One Thousand Four Hundred',
        ], currency: 'INR'),
        147000,
      );
    });

    test('words a digit away from an unbacked total: flagged, not chosen', () {
      // The faint SESENTA lost from the words, and one item misread, so
      // nothing settles 3,760 against 3,700.
      for (final change in <String, String?>{
        r'5  Cuervo Reposado @$110  $550.00': r'5  Cuervo Reposado @$110  $580.00',
        r'1  Limonada @$59.00  $59.00': null,
      }.entries) {
        final parsed = parse(misread({
          '(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)':
              '(**TRES MIL SETECIENTOS PESOS 00/100 **)',
          change.key: change.value,
        }));
        expect(parsed.amountDoubtful, isTrue, reason: change.key);
        expect(parsed.amountMinor, anyOf(376000, 370000));
      }
    });
  });

  group('date', () {
    void expectDate(ParsedReceipt p, DateTime? date, {bool flagged = false}) {
      expect(p.date, date);
      if (date != null) expect(p.dateDoubtful, flagged);
    }

    test('a due or delivery date on the same row as the purchase date', () {
      final day = DateTime(2026, 11, 12);
      expectDate(
        parse([
          'MATERIALES EL ROBLE SA DE CV',
          'PEDIDO: 1234 05/11/2026',
          'FECHA: 12/11/2026  VENCE: 12/12/2026',
          'TOTAL 1,000.00',
        ]),
        day,
      );
      expectDate(
        parse(['FERRETERIA', 'FECHA: 12/11/2026  VENCE: 12/12/2026', 'TOTAL 1.00']),
        day,
      );
      expectDate(
        parse([
          'TELMEX',
          'Fecha de emision: 10/11/2026 Fecha limite de pago: 25/11/2026',
          'TOTAL A PAGAR 599.00',
        ]),
        DateTime(2026, 11, 10),
      );
      expectDate(
        parse([
          'TINTORERIA LA ESTRELLA',
          'Recibido: 12/11/2026  Entrega: 15/11/2026',
          'TOTAL 120.00',
        ]),
        day,
      );
      expectDate(
        parse(['PIZZERIA', 'Fecha: 12/11/2026 18:02 Servicio: Entrega', 'TOTAL 245.00']),
        day,
      );
      expectDate(
        parse(['VALE', 'VALIDO HASTA 31/12/2026', 'FECHA 12/11/2026', 'TOTAL 1.00']),
        day,
      );
    });

    test('a number before the date does not swallow it', () {
      expectDate(
        parse(['FARMACIA EJEMPLO', 'CAJA: 19 - 30/09/2026 12:49', 'TOTAL 31.42']),
        DateTime(2026, 9, 30),
      );
      for (final row in [
        'MESA 5 - 28/07/2026 14:42',
        '14:42 - 28/07/2026',
      ]) {
        expectDate(parse(['REST', row, 'TOTAL 45.00']), DateTime(2026, 7, 28));
      }
      for (final row in ['CAJA 1 - 12/11/2026 18:02', 'TURNO 2 / 12/11/2026']) {
        expectDate(parse(['TIENDA', row, 'TOTAL 45.00']), DateTime(2026, 11, 12));
      }
      expectDate(
        parse(
          ['DINER', 'TABLE 5 - 10/26/2026 6:02 PM', 'TOTAL 45.00'],
          currency: 'USD',
          monthFirst: true,
        ),
        DateTime(2026, 10, 26),
      );
    });

    test('a street named after a date is not the date', () {
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO',
          'AV. 5 DE MAYO 12 CENTRO',
          r'Total $3,760.00',
          'Ticket: 20260728-001-100001-00001',
        ]),
        DateTime(2026, 7, 28),
        flagged: true,
      );
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO',
          'AV. 20 DE NOVIEMBRE 25 CENTRO',
          r'Total $3,760.00',
        ]),
        null,
      );
    });

    test('weekdays, item names and times are not a second date', () {
      expectDate(
        parse(['TAQUERIA EL PASTOR', '10/11/26 MAR 14:42', '2 TACOS 60.00', 'TOTAL 60.00']),
        DateTime(2026, 11, 10),
      );
      expectDate(
        parse([
          'OXXO',
          'TIENDA 50XYZ',
          '12/11/2026 18:02',
          '1 MARUCHAN 18.50',
          'TOTAL 18.50',
        ]),
        DateTime(2026, 11, 12),
      );
      expectDate(
        parse(['REST', '12.11.2026 10.05.26', 'TOTAL 45.00']),
        DateTime(2026, 11, 12),
      );
    });

    test('a version number is not a date', () {
      expectDate(parse(['CAFE LA OLLA', 'TOTAL 80.00', 'Sistema POS v1.10.26']), null);
    });
  });

  group('merchant', () {
    test('a big heading is not the name', () {
      final p = ReceiptTextParser(defaultCurrency: 'USD', clock: clock).parse(
        const OcrResult(text: '', lines: [
          OcrLine(text: 'CAFE EJEMPLO', left: 200, top: 10, right: 400, bottom: 40),
          OcrLine(text: 'GRUPO EJEMPLO ALIMENTOS, SA DE CV', left: 20, top: 50, right: 700, bottom: 80),
          OcrLine(text: 'SAN SALVADOR', left: 20, top: 90, right: 300, bottom: 120),
          OcrLine(text: 'PRECOUENTA', left: 200, top: 140, right: 500, bottom: 230),
          OcrLine(text: 'TOTAL 31.42', left: 20, top: 400, right: 300, bottom: 430),
        ]),
      );
      expect(p.merchant, 'Cafe Ejemplo');
    });
  });

  test('Cafe Ejemplo receipt as the phone read it (columns come out apart)', () {
    final parsed = parse(_cafeText.split('\n'), currency: 'USD');
    // The time after "TOTAL" is not the amount, and the numbers climb like a
    // bill: items 28.23, plus tip 3.19, total 31.42.
    expect(parsed.amountMinor, 3142);
    expect(parsed.amountDoubtful, isFalse);
    expect(parsed.date, DateTime(2026, 9, 30));
    expect(parsed.merchant, 'Cafe Ejemplo');
  });

  test('Cafe Ejemplo photo tilted: name joined to the company line', () {
    OcrLine line(String text, double left, double top, double right,
            [double h = 30]) =>
        OcrLine(text: text, left: left, top: top, right: right, bottom: top + h);
    final parsed = ReceiptTextParser(defaultCurrency: 'USD', clock: clock)
        .parse(OcrResult(text: '', lines: [
      // The tilt puts CAFE EJEMPLO level with the right half of the next line.
      line('CAFE EJEMPLO', 300, 40, 520, 34),
      line('GRUPO EJEMPLO ALIMENTOS, SA DE CV', 20, 52, 700),
      line('NRC.100000-1', 40, 100, 300),
      line('NIT.0000-000000-000-0', 330, 100, 700),
      line('GIRO:RESTAURANTES, Y ACTIVIDADES VARIAS', 20, 140, 720),
      line('DE RESTAURANTES', 250, 180, 520),
      line('C.EJEMPLO, L.1,COL.CENTRO, TORRE UNO,', 20, 220, 720),
      line('SAŃ SALVADOR, SAN ŚALVADOR.', 150, 236, 640),
      line('PREQUENTA', 260, 300, 460, 60),
      line('SUBTOTAL \$', 350, 900, 520),
      line('28.23', 600, 890, 700),
      line('PROPINA \$', 340, 940, 520),
      line('3.19', 620, 930, 700),
      line('TOTAL \$', 350, 980, 520),
      line('31.42', 600, 970, 700),
    ]));
    expect(parsed.merchant, 'Cafe Ejemplo');
    expect(parsed.amountMinor, 3142);
  });

  test('Cafe Ejemplo tilted: each price read twice, labels beside other amounts',
      () {
    final parsed = parse([
      'CAFE EJEMPLO  GRUPO EJEMPLO ALIMENTOS, SA DE CV',
      'CAJA: 19  30/09/2026  12:49',
      'COCA ZERO BOT',
      '1.00  x  2.21=',
      'COCA COLA BOT  2.21E',
      '1.00  x  2.21=',
      'PARIS WARM BOWL  2.21E',
      '1.00  x  12.35=',
      'CRISPY QUINOA CHICKEN SALAD  12.35E',
      '1.00  x  11.46=',
      '11.46E',
      r'SUBTOTAL $',
      r'28.23  PROPINA $',
      r'3.19  TOTAL $',
      '31.42',
    ], currency: 'USD');
    expect(parsed.amountMinor, 3142);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('Venezuelan till screen: no shop name printed, so none is made up', () {
    final parsed = parse(_xetuxText.split('\n'), currency: 'VES');
    expect(parsed.amountMinor, 5214442);
    expect(parsed.date, DateTime(2026, 9, 14));
    expect(parsed.merchant, isNull);
  });

  test('coffee shop read badly: card line, items, words and dates still agree',
      () {
    final parsed = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 18, 22),
    ).parseRows(_coffeeText.split('\n'));
    // "Pagado Total S1.00 11.00" is a damaged row; the card payment, the two
    // items (114.00 + 97.00) and the amount in words all say 211.00.
    expect(parsed.amountMinor, 21100);
    expect(parsed.amountDoubtful, isFalse);
    expect(parsed.date, DateTime(2026, 11, 16)); // "Nov16'26", "16-1 1-2026"
    expect(parsed.dateDoubtful, isFalse);
    expect(parsed.merchant, 'Starbucks'); // from "stabckS"
  });

  test("month, day and a two-digit year after an apostrophe", () {
    final later = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 18),
    );
    expect(later.parseRows(['CAFE', "Nov16'26 03:12PM", 'TOTAL 10.00']).date,
        DateTime(2026, 11, 16));
    expect(later.parseRows(['CAFE', "NOV 3 '26", 'TOTAL 10.00']).date,
        DateTime(2026, 11, 3));
  });
}

const _cafeText = '''GRUPO EJEMPLO ALIMENTOS, SA DE CV
NRC.100000-1
NIT.0000-000000-000-0
GIRO:RESTAURANTES, Y ACTIVIDADES VARIAS
DE RESTAURANTES
CAFE EJEMPLO
C.EJEMPLO, L.1,COL.CENTRO, TORRE UNO,
SAN SALVADOR, SAN SALVADOR.
MESA: 20
Codigo: 10001
Cliente: JUAN PEREZ
TEL: 00000000
SAN SALVADOR
CAJA: 19
FORMA DE PAGO:
PREQUENTA
COCA ZERO BOT
1.00
COCA COLA BOT
1.00
1.00
PARIS WARM BOWL
30/09/2026
1.00
X
2.21=
X 2.21=
X 12.35=
CRISPY QUINOA CHICKEN SALAD
X 11.46=
SUBTOTAL \$
PROPINA \$
TOTAL
12:49
2.21E
2.21E
12.35E
11.46E
28.23
3.19
31.42
NOTA: ESTE COMPROBANTE "SALDO DE MESA"
NO SUSTITUYE EL TICKET FISCAL.
EXIJA TICKET, FACTURA O CREDITO FISCAL''';

const _xetuxText = '''1OMeAPERTURA
PERS
silla 1
ORDEN/SUB-ORDEN:100001/100002
Co
de
09/14/2026 19:56:12
CLIENTE JUAN PEREZ
NOMBRE
SWE SWEET AND SPICY
PEPSI RETORNABLE
DOUBLE PEPPERONI
PEPSI RETORNABLE
Exija su factura
FECHA:09/14/2026 19:56:12
Base
Descuentos
Recargos
Sub Total
Impuestos
Bs.S1.815 17 x3
Servicio
Bs Sl0. 164,60 2
Bs Si0 164,60x1
Bs.SI 815,1 1 X3
Total sin Servicio
Bs. S5.445,32
Tasa del día:Bs.S842,21
Bs. S20.329,21
Bs.S10. 164,60
Bs. S5.445,32
Bs.S41.384,46
Bs.S0,00
Bs.S0,00
Bs.S41.38446
Bs.S6.621,51
Bs.S48.005,97
Bs.S4.138,45
Total Bs.S52.144,42
RECH
etux''';

const _coffeeText = '''tatCKs Coffee En Son
Expedido en:
Hoeo N S00 LOcal PB
CP 110hpultepec Ejemplo  Col.
Del. Ejemplo
Ciudad de MexiCo
1000 CAJA
Chk 1000  200000001  Gst
Nov16'26 03:12PM
Oby
1 VT Berry Pear1s Le  114.00
VT PaT-COMP Nitro
1  GD CaraTel F  97.00
GO L Entera F
reTa Bat icda
GO POT-COMP Plano
alU FR/Base Cafe  GD
3361
VISA CREDITO  211.00
Pagado  Total  S1.00  11.00
1000 Check CloSed-
-NOV16'26 03: 14PM-
DosCientos OnCe pess,(0/100 M.
N
I.V.A INCLUIDO
PUedes SoliCitar tu factua
Datos pra Factuar=
Ticket : 200000001
Tiena  10000
Fecha  16-1 1-2026
REGIMEN FISCAL:  N/A
Cafe Ejemplo, S.A. de C.V.
Centro de AtenCion a Clientes
tuopinion@stabckS.COn -mK
DONA AQUI''';

import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_notes.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bakery-café ticket (numbers and addresses made generic): a survey
/// request above the company name, the date as "23 Nov'26", choices under
/// each drink, a discount line, the tip and the invoice reference.
const ticket = [
  'TICKET #10001',
  'Por favor ayudanos contestando la',
  'encuesta escaneando el siguiente',
  'codigo QR con tu celular o tableta',
  '====================================',
  'ERIC KAYSER MEXICO SAPI DE C.V.',
  'REGIMEN GENERAL DE LEY PM',
  'R.F.C. XXX010101AB1',
  'AV. EJEMPLO No 1400 PISO 9',
  'COL. EJEMPLO INN ALC. ALVARO OBREGON',
  'CIUDAD DE MEXICO C.P. 01020',
  '10001 Cajero',
  '------------------------------------',
  'Cuenta 10001',
  "23 Nov'26 08:59 AM",
  '------------------------------------',
  'Vitrina',
  '1 MALTEADA C CHOCOLATE CH 155.00',
  'VASO DESECHABLE',
  'CAMBIO L. LIGHT',
  '1 NUTELLA LATTE FRAPPE GD 145.00',
  'L. ENTERA',
  'VASO DESECHABLE',
  '1 EXTRA CREMA BATIDA 20GR 27.00',
  '1 LIMONADA 88.00',
  'MINERAL',
  '1 Desc. 10% AICM -41.50',
  'AICM',
  '10.00 %',
  r'Subtotal $373.50',
  r'Otro $18.65',
  r'Total Pagado $392.15',
  r'Cambio $0.00',
  r'Propina Tarjeta $18.65',
  r'Tarjeta Credito $392.15',
  '----------- Ticket cerrado -----------',
  "23 Nov'26 09:02 AM",
  'Gracias por su compra',
  'Siempre le esperamos en Maison Kayser,',
  'Su rincon de Paris en Mexico.',
  'Av. Ejemplo Gonzalez S/N',
  'Local AS-01 Terminal 2',
  'Col. Zona Federal Aeropuerto',
  'Internacional Alc VC CP 15620',
  'SUCURSAL:K CHECKIN T2',
  'SI DESEA FACTURAR INGRESE A',
  'http://www.maison-kayser.com.mx/',
  '¿PROBLEMA DE FACTURACION?',
  'facturas@maison-kayser.com.mx',
  'Referencia de facturacion:',
  '01000000000001',
];

void main() {
  ParsedReceipt parse(List<String> rows) => ReceiptTextParser(
        defaultCurrency: 'MXN',
        clock: () => DateTime(2026, 11, 23, 9, 16),
      ).parseRows(rows);

  test('date with an apostrophe year, brand over the survey request', () {
    final p = parse(ticket);
    expect(p.date, DateTime(2026, 11, 23));
    expect(p.dateDoubtful, isFalse);
    expect(p.amountMinor, 39215);
    expect(p.merchant, 'Maison Kayser');
  });

  test('without the brand line the company is named, never the survey', () {
    final p = parse([
      for (final r in ticket)
        if (!r.contains('Maison Kayser')) r,
    ]);
    expect(p.merchant, 'Eric Kayser Mexico');
  });

  test('other ways tills print a short year', () {
    for (final row in ["23 Nov'26 08:59", '23 Nov’26', '23-Nov-26', "23 NOV '26"]) {
      expect(parse(['CAFE EJEMPLO', row, 'TOTAL 50.00']).date,
          DateTime(2026, 11, 23),
          reason: row);
    }
  });

  test('every item, its choices, and the discount; stops at the totals', () {
    final items = ItemLineParser.extract(ticket);
    expect([for (final i in items) '${i.description}|${i.amountText ?? ''}'], [
      'MALTEADA C CHOCOLATE CH|155.00',
      'VASO DESECHABLE|',
      'CAMBIO L. LIGHT|',
      'NUTELLA LATTE FRAPPE GD|145.00',
      'L. ENTERA|',
      'VASO DESECHABLE|',
      'EXTRA CREMA BATIDA 20GR|27.00',
      'LIMONADA|88.00',
      'MINERAL|',
      'Desc. 10% AICM|-41.50',
    ]);
  });

  test('"CAMBIO" with an amount is still the change given', () {
    final items = ItemLineParser.extract([
      '1 CAFE AMERICANO 45.00',
      '1 PAN DULCE 25.00',
      'TOTAL 70.00',
      'EFECTIVO 100.00',
      'CAMBIO 30.00',
    ]);
    expect([for (final i in items) i.description], ['CAFE AMERICANO', 'PAN DULCE']);
    expect(ItemLineParser.isSummaryRow(r'Cambio $0.00'), isTrue);
    expect(ItemLineParser.isSummaryRow('SU CAMBIO: 30.00'), isTrue);
    expect(ItemLineParser.isSummaryRow('CAMBIO L. LIGHT'), isFalse);
  });

  test('a heading between items is not a choice; a two-row item is not one '
      'either', () {
    final items = ItemLineParser.extract([
      '1 CAFE AMERICANO 45.00',
      'LECHE ENTERA',
      'BEBIDAS',
      'JUGO NARANJA',
      '1.00 x 60.00 60.00',
      'TOTAL 105.00',
    ]);
    expect([for (final i in items) '${i.description}|${i.amountText ?? ''}'],
        ['CAFE AMERICANO|45.00', 'LECHE ENTERA|', 'JUGO NARANJA|60.00']);
  });

  test('a unit price beside its line total is not taken for a date', () {
    final items = ItemLineParser.extract([
      '2 AGUA MINERAL 45.00 90.00',
      '1 CAFE 15.11.26 35.00',
      'TOTAL 125.00',
    ]);
    expect([for (final i in items) '${i.description}|${i.amountText}'],
        ['AGUA MINERAL|90.00', 'CAFE|35.00']);
  });

  test('notes: invoice site, reference on the next line, help address, tip, '
      'discount; no note for a survey with no reward', () {
    final notes = ReceiptNotes.find(ticket);
    final invoice = notes.firstWhere((n) => n.kind == ReceiptNoteKind.invoice);
    expect(invoice.detail, contains('Online: http://www.maison-kayser.com.mx/'));
    expect(invoice.detail, contains('Invoice reference (folio): 01000000000001'));
    expect(invoice.detail, contains('Invoice help: facturas@maison-kayser.com.mx'));
    expect(notes.firstWhere((n) => n.kind == ReceiptNoteKind.tip).title,
        'Tip on this receipt: 18.65');
    expect(notes.firstWhere((n) => n.kind == ReceiptNoteKind.discount).title,
        'Discount already applied: 10% (-41.50)');
    expect(notes.where((n) => n.kind == ReceiptNoteKind.offer), isEmpty);
  });

  test('an address read with spaces round its dots is put back together; '
      'words after the label are never a reference', () {
    final notes = ReceiptNotes.find([
      'SI DESEA FACTURAR INGRESE A',
      'http://www.example-cafe.com. mx/',
      'Referencia de facturacion:',
    ]);
    final invoice = notes.single;
    expect(invoice.detail, contains('Online: http://www.example-cafe.com.mx/'));
    expect(invoice.detail, isNot(contains('folio')));
  });

  test('a zero or blank tip line says nothing', () {
    expect(ReceiptNotes.find([r'Propina $0.00', 'TOTAL 90.00']), isEmpty);
    expect(ReceiptNotes.find(['PROPINA: ________', 'TOTAL 90.00']), isEmpty);
    expect(
        ReceiptNotes.find(['Propina sugerida 10% 37.35', 'TOTAL 90.00']), isEmpty);
  });
}

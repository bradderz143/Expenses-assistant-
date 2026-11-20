import 'package:expense_assistant/domain/logic/item_classifier.dart';
import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_text_lines.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fast-food kiosk ticket as the phone read it (numbers made generic):
/// prices with one decimal, the brand only lower down ("KEC" for KFC),
/// the operating company's legal name on top.
const ticket = [
  '409',
  'PREMIUM RESTAURANI BRANDS SDE RI DE CV',
  'PASEO DE DAMARIND08 400 PISO1',
  'BOSQUES DE I.AS LOMAS, CUAUIMALPA',
  'CIUDAD DE MXICO, 05120',
  'RFC XXX010101AB1',
  'PERSONA MORAT. REGTMEN GENERAL DE LEY',
  '20:04  11/19/26 K4-0409',
  '#409  LLEVAR',
  'KIOSKO',
  'CLIENTE',
  '2 REFRE SCO  887 ML  110.0',
  '1 COLA 887 ML  0.0',
  '2 PAPAS FAM  190.0',
  'TOTAL M.N.:  300,00',
  'Trasoientos Pesos 00/100 M.N.',
  'VENTA',
  'PAGO TARJE TA C/TERMINAL',
  'TARJETA: 411111** ****1111',
  'AUTORIZACION: X0XXXX',
  'APROBADO EN LINEA',
  'KEC POLANCO',
  'ARQUIMEDE S 235',
  'POILANCO V SECCION C.P.11560',
  'MIGUEL HIDALGO, CIUDAD DE MEXICO',
  'No. tioket unioo: 409',
  'KEC Corporation',
  'AFILIACION: 1000001',
  'IMPORTE: 300,00',
];

void main() {
  test('the brand printed lower down beats the legal name; total and date',
      () {
    final p = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 20, 9),
    ).parseRows(ticket);
    expect(p.merchant, 'KFC');
    expect(p.amountMinor, 30000);
    expect(p.date, DateTime(2026, 11, 19));
  });

  test('one-decimal prices are items, stopping at the total', () {
    final items = ItemLineParser.extract(ticket);
    expect([for (final i in items) i.description],
        ['REFRE SCO 887 ML', 'COLA 887 ML', 'PAPAS FAM']);
    expect([for (final i in items) i.amountText], ['110.00', '0.00', '190.00']);
    expect([for (final i in items) i.quantity], ['2', '1', '2']);
  });

  test('a single number with one decimal is not taken as a price', () {
    expect(ItemLineParser.extract(['AGUA NATURAL 1.5', 'TOTAL 25.00']), isEmpty);
  });

  test('split words are joined; fast-food words made plain for the model',
      () {
    expect(ItemWording.rejoin('REFRE SCO 887 ML'), 'REFRESCO 887 ML');
    expect(ItemWording.rejoin('PAGO TARJE TA C/TERMINAL'),
        'PAGO TARJETA C/TERMINAL');
    expect(ItemWording.rejoin('ARQUIMEDE S 235'), 'ARQUIMEDE S 235');
    expect(ItemWording.expandAbbreviations('COLA 887 ML', 'es'),
        'refresco de cola 887 ML');
    expect(ItemWording.expandAbbreviations('COCA COLA', 'es'), 'COCA COLA');
    expect(ItemWording.expandAbbreviations('PAPAS FAM', 'es'),
        'papas fritas familiares');
    expect(ItemWording.expandAbbreviations('#409 LLEVAR', 'es'),
        '#409 para llevar');
    expect(ItemWording.expandAbbreviations('PARA LLEVAR', 'es'), 'PARA LLEVAR');
  });

  test('an amount in words gets an exact English translation', () {
    expect(KnownPhrases.translate('Trasoientos Pesos 00/100 M.N.', 'es'),
        'Three hundred pesos 00/100 (national currency)');
    expect(KnownPhrases.numberInEnglish(3760),
        'three thousand seven hundred sixty');
    expect(KnownPhrases.translate('PAPAS FAM', 'es'), isNull);
  });

  test('receipt text drops tax IDs and card numbers, keeps addresses as '
      'printed', () {
    final lines = ReceiptTextLines.meaningful(ticket);
    for (final gone in [
      'RFC XXX010101AB1',
      'PERSONA MORAT. REGTMEN GENERAL DE LEY',
      'TARJETA: 411111** ****1111',
    ]) {
      expect(lines, isNot(contains(gone)), reason: gone);
    }
    final kept = ReceiptTextLines.asPrinted(lines);
    final printed = {for (final i in kept) lines[i]};
    expect(
      printed,
      containsAll([
        'PREMIUM RESTAURANI BRANDS SDE RI DE CV',
        'PASEO DE DAMARIND08 400 PISO1',
        'BOSQUES DE I.AS LOMAS, CUAUIMALPA',
        'CIUDAD DE MXICO, 05120',
        'POILANCO V SECCION C.P.11560',
        'MIGUEL HIDALGO, CIUDAD DE MEXICO',
      ]),
    );
    expect(printed, isNot(contains('2 PAPAS FAM 190.0')));
    expect(printed, isNot(contains('KIOSKO')));
  });
}

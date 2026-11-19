import 'package:expense_assistant/domain/logic/item_classifier.dart';
import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_text_lines.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card-terminal slip as the phone read it (numbers made generic).
const slip = [
  'CORRESPONSAL CAMBIARIO DE BANCO EJEMPLO, S.A.',
  'INSTITUCION DE BANCA MULTIPLE',
  'XXX010101AB1-DUFRY EJEMPLO SA DE CV',
  'XYZ015 SHOP 2104 T1',
  'XX*** X*****',
  'TRANSACCI NELECTRONICA DE VENTA',
  'X******X XX***XX*****X*XXX****',
  'Tienda 15 Caja 1',
  'Fecha 14.09.2026 Hora 00:17 Ticket10001',
  'GETNET',
  'AFILIACION: 1000001',
  'TERMINAL ID: 10000001',
  'NUMERO DE CONTROL:',
  'REFERENCIA:',
  'NUM. TARJETA: ************0000',
  'BANCO EMISOR:',
  'TIPO TARJETA:',
  'TARJETA HABIENTE:',
  'TIPO LECTURA: MSR',
  'TIPO TRANSACCION: VENTA',
  'IMPORTE TOTAL MXN: 570.00',
  'ACEPTADA',
  'CREDITO (1 MESES SIN INTERESES )',
  'POR ESTE PAGARE ME OBLIGO INCONDICIONAL-',
  'MENTE A PAGARA LA ORDEN DEL BANCO ACRE-',
  'DITANTE EL IMPORTE DE ESTE TITULO. ESTE',
  'PAGARE PROCEDE DEL CONTRATO DE APERTURA',
  'DE CREDITO QUE EL BANCO ACREDITANTE Y EL',
  'TARJETA HABIENTE TIENE CELEBRADO',
  'AUTORIZACION: 000001',
  'ID PBX: S00015P001-10000-000000001',
  'TR, NO VTOL: 1000',
  'AUTORIZADO CON PIN ELECTRONICO',
  'POR FAVOR CONSERVE ESTE TICKET',
];

void main() {
  test('a card slip keeps the lines that matter, without reference noise',
      () {
    final lines = ReceiptTextLines.meaningful(slip);
    for (final noise in [
      'XX*** X*****',
      'X******X XX***XX*****X*XXX****',
      'AFILIACION: 1000001',
      'TERMINAL ID: 10000001',
      'NUMERO DE CONTROL:',
      'BANCO EMISOR:',
      'NUM. TARJETA: ************0000',
      'AUTORIZACION: 000001',
      'ID PBX: S00015P001-10000-000000001',
      'TR, NO VTOL: 1000',
    ]) {
      expect(lines, isNot(contains(noise)), reason: noise);
    }
    expect(lines, contains('IMPORTE TOTAL MXN: 570.00'));
    expect(lines, contains('Fecha 14.09.2026 Hora 00:17 Ticket10001'));
    expect(lines, contains('TIPO TRANSACCION: VENTA'));
    // The wrapped legal paragraph is one line again.
    final clause = lines.singleWhere((l) => l.startsWith('POR ESTE PAGARE'));
    expect(clause, contains('INCONDICIONALMENTE A PAGARA'));
    expect(clause, endsWith('TARJETA HABIENTE TIENE CELEBRADO'));
  });

  test('standard card-slip wording has a fixed translation', () {
    expect(
      KnownPhrases.translate(
          'POR ESTE PAGARE ME OBLIGO INCONDICIONALMENTE A PAGAR', 'es'),
      startsWith('By this promissory note'),
    );
    expect(KnownPhrases.translate('AUTORIZADO CON PIN ELECTRONICO', 'es'),
        'Authorised with PIN');
    expect(KnownPhrases.translate('TIPO LECTURA: MSR', 'es'), isNull);
    expect(KnownPhrases.translate('POR ESTE PAGARE', 'pt'), isNull);
  });

  test('card-slip terms are made plain before machine translation', () {
    expect(ItemWording.expandAbbreviations('TARJETA HABIENTE:', 'es'),
        'titular de la tarjeta:');
    expect(ItemWording.expandAbbreviations('Tienda 15 Caja 1', 'es'),
        'Tienda 15 caja registradora 1');
  });

  // A Venezuelan till screen as the phone read it.
  const screen = [
    'ORDEN/SUB-ORDEN 100001/1 00002',
    'APERTURA 09/14/2026 19:56:12',
    'FECHA :09/14/2026 19:56:12  PRECH',
    'CLIENTE JUAN PEREZ',
    'NOMBRE',
    'PEPSI RETORNABLE  Bs.S1.81511 x',
    'Bs. S5.445,32',
    'DOUBLE PEPPERONI  Bs S10. 164,60',
    'x2  Bs. S20.329,21',
    'SHEL SWEET AND SPICY  Bs S10',
    'I64,60 x  Bs. S10. 164,60',
    'PEPSI RETORNABLE  Bs.SI.815,1 1',
    'X3  Bs. S5.445,32',
    'PEPS',
    'Base  Bs.S41.38446',
    'Descuentos  Bs.S0,00',
    'Recargos  Bs.S0,00',
    'Sub Total  Bs.S41.38446',
    'Impuestos  Bs.S6.621,51',
    'Total sin Servicio  Bs.S48.005,97',
    'Servicio  Bs.S4.138,45',
    'o Total Bs.S52.144,42',
    'Tasa del día:Bs.S842,21',
    'Exija su factura  etux',
  ];

  test('items priced in "Bs.S" and wrapped onto the next row are found', () {
    final names = ItemLineParser.extract(screen).map((i) => i.description);
    expect(names, contains('PEPSI RETORNABLE'));
    expect(names, contains('DOUBLE PEPPERONI'));
    expect(names.length, greaterThanOrEqualTo(3));
  });

  test('a cut-off "PRECIO" column heading is not the merchant', () {
    final parsed = ReceiptTextParser(
      defaultCurrency: 'VES',
      clock: () => DateTime(2026, 11, 18),
    ).parseRows(screen);
    expect(parsed.merchant, isNot('Prech'));
    expect(parsed.amountMinor, 5214442);
    expect(parsed.date, DateTime(2026, 9, 14));
  });
}

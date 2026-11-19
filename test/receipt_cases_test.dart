import 'package:expense_assistant/domain/logic/receipt_text_lines.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:expense_assistant/domain/reference/countries.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real receipts that were read wrongly, kept as regression cases.
void main() {
  DateTime clock() => DateTime(2026, 11, 4, 12);

  test('Dufry: S/N in the address is not soles; brand beats the bank header', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock).parseRows([
      'CORRESPONSAL CAMBIARIO DE BANCO EJEMPLO, S.A.',
      'INSTITUCION DE BANCA MULTIPLE',
      'XXX010101AB1-DUFRY EJEMPLO SA DE CV',
      'XYZ015 SHOP 2104 T1',
      'AV. EJEMPLO S/N, COLONIA P',
      'Fecha 14.09.2026 Hora 00:17 Ticket10001',
      'IMPORTE TOTAL MXN: 570.00',
    ]);
    expect(parsed.currency, 'MXN');
    expect(parsed.merchant, 'Dufry');
    expect(parsed.amountMinor, 57000);
  });

  test('a lone S/N never means Peruvian soles', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
        .parseRows(['TIENDA', 'AV. EJEMPLO S/N', 'TOTAL 570.00']);
    expect(parsed.currency, 'MXN');
  });

  test('Hotel Ejemplo: spaced-out total and doubled capital', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'VES', clock: clock).parseRows([
      'SENIAT',
      'HHotel Ejemplo & Spa, S.C-S',
      'RIF: J-00000001-1',
      'FACTURA # 00018997',
      'FECHA 18/09/2026 10:20',
      'BI G 16.00% 623.200,25',
      'IVA G 16.00% 99.712,04',
      'PAGO DIVISA 722.912,29',
      'IGTF 3% 21.687,37',
      'TOTAL Bs: 744 . 599 , 66',
      'Freedom Pay Master "Bs." 736046.03',
      'Diferencia en Cambio "Bs." 8553.63',
    ]);
    expect(parsed.amountMinor, 74459966);
    expect(parsed.merchant, startsWith('Hotel Ejemplo'));
    expect(parsed.currency, 'VES');
  });

  test('Ejemplo: misread total corrected from subtotal + IVA and card payment', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'VES', clock: clock).parseRows([
      'SENIAT',
      'J-000000002',
      'EJEMPLO 360, C.A',
      'CHACAO CARACAS (CHACAO) MIRANDA',
      'SUBTTL Bs 60.585,16',
      'BI G (16,00%) Bs 60.585,16',
      'IVA G (16,00%) Bs 9.693,63',
      'TOTAL Bs 78.276,79',
      'PUNTO DE VENTA Bs 70.278,80',
      'CAMBIO Bs 0,01',
    ]);
    expect(parsed.merchant, 'Ejemplo 360');
    expect(parsed.amountMinor, 7027879);
    expect(parsed.amountDoubtful, isFalse);
  });

  test('card slip with a tip: the amount charged wins (matches the statement)', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'VES', clock: clock).parseRows([
      'EJEMPLO 360, C.A',
      'J-000000002',
      'Compra',
      'AID: A0000000041010 MASTERCARD DEBITO',
      'MONTO: Bs 76.337,31',
      '00, APROBADO',
      'SUBTTL Bs 60.585,16',
      'IVA G (16,00%) Bs 9.693,63',
      'TOTAL Bs 70.278,79',
    ]);
    expect(parsed.amountMinor, 7633731);
  });

  test('no card slip: the bill total stands', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
        .parseRows(['LA PARRILLA', 'IMPORTE 520.00', 'TOTAL 450.00']);
    expect(parsed.amountMinor, 45000);
  });

  test('tip paid by card on the bill itself is claimed', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
        .parseRows(['LA PARRILLA', 'TOTAL 428.50', 'PROPINA 42.85', 'VISA 471.35']);
    expect(parsed.amountMinor, 47135);
  });

  test('cash handed over is never the amount', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
        .parseRows(['LA PARRILLA', 'TOTAL 428.50', 'EFECTIVO 500.00', 'CAMBIO 71.50']);
    expect(parsed.amountMinor, 42850);
  });

  const taxiRows = [
    'AEROPUERTO INTERNACIONAL DE LA CIUDAD DE MEXICO',
    'XXX010101AB1 EJEMPLO S.A. DE C.V',
    'CALLE EJEMPLO 100, COL. CENTRO',
    'C.P.: 15000 TEL: (55) 0000-0000 Con 10 Linea',
    'ZONA: 7 CENTRO',
    'DELEGACION EJEMPLO',
    'TARIFA: \$440.00 PASAJERO',
    'FECHA 2026-09-18 22:19',
    'TIPO PAGO: VISA YELLOW CAB',
    'SERVICIO: SEDAN',
    '4 PASAJEROS MAX',
    'UN SOLO DESTINO',
    '220000000000001',
    'FACTURACION:',
    'www.ejemplo.mx',
    'BOLETO VIGENTE POR 30 DIAS',
  ];

  test('airport taxi: merchant, fare and date', () {
    final parsed = ReceiptTextParser(defaultCurrency: 'MXN', clock: clock)
        .parseRows(taxiRows);
    expect(parsed.merchant, 'Yellow Cab');
    expect(parsed.amountMinor, 44000);
    expect(parsed.date, DateTime(2026, 9, 18));
    expect(Countries.detectInText(taxiRows.join('\n')), 'Mexico');
  });

  test('non-meal receipts translate the meaningful lines only', () {
    final lines = ReceiptTextLines.meaningful(taxiRows);
    expect(lines, contains('TARIFA: \$440.00 PASAJERO'));
    expect(lines, contains('FECHA 2026-09-18 22:19'));
    expect(lines, contains('UN SOLO DESTINO'));
    expect(lines, isNot(contains('220000000000001')));
    expect(lines, isNot(contains('www.ejemplo.mx')));
  });

  test('country from Venezuelan clues and from a single-country currency', () {
    expect(Countries.detectInText('SENIAT\nEJEMPLO 360'), 'Venezuela');
    expect(Countries.fromCurrency('VES'), 'Venezuela');
    expect(Countries.fromCurrency('MXN'), 'Mexico');
    expect(Countries.fromCurrency('USD'), isNull); // El Salvador, Ecuador…
    expect(Countries.fromCurrency('EUR'), isNull);
  });
}

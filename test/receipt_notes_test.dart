import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_notes.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A coffee-shop receipt (numbers and addresses made generic).
const coffee = [
  'COSTA COFFEE',
  'SANTA CLARA MERCANTIL DE',
  'PACHUCA S. DE R.L DE C.V',
  'RFC: XXX010101AB1',
  'SUC. 1000001 EJEMPLO MUSSET',
  'COL. POLANCO, CIUDAD DE MEXICO, CP 115',
  'Recepción: XXXXXX 20/11/2026',
  'CAJA-0001 1:32 PM',
  '1000009',
  'Caramel lced WVhip L Media 100.00',
  'Leche Deslactosada MD',
  'Chocolate Frappe Grandę 104.00',
  'Sub-total 175.86',
  'Impuestos 28.14',
  'KIOSKO PL Total 204.00',
  r'CREDITO Nº 0000 $204.00',
  '- Cuenta cerrada -',
  '¡GRACIAS POR SU COMPRA!',
  'FACTURACION',
  'Si requiere factura solicitela en el',
  'momento de la compra en el',
  'establecimiento o si lo prefiere,',
  'puede ingresar a:',
  'https://facturas.example.com/facturacion',
  'CUENTA CON 30 DIAS PARA REALIZAR',
  'FACTURACION',
  '¿Tienes comentarios,quejas o sugerencia?',
  'Llamanos al 800 000 0000',
  'Para acceder al sanitario, teclea:',
  '1234#',
];

/// The bottom of a fast-food ticket.
const fastFood = [
  'TOTAL M.N.: 300,00',
  'No. ticket unico: 409',
  'Folio para facturar: 0000000000000001',
  'Solicita tu Factura Electronica',
  'al momento del pago del consumo.',
  'Consulta nuestro aviso de privacidad en:',
  'www.example.com.mx',
  'Internet CLIENTES-WIFI',
  'Password: Secret123',
  'Queremos escuchar tu opinion',
  'Responde nuestra encuesta de satisfaccion',
  'y llevate unas Papas Chicas gratis',
  'en tu proxima visita.',
  'Entra a: www.encuesta-example.com',
];

void main() {
  test('coffee receipt: brand, not the company split over two lines', () {
    final p = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 20, 14),
    ).parseRows(coffee);
    expect(p.merchant, 'Costa Coffee');
    expect(p.amountMinor, 20400);
    // Without the brand line, the split legal name is still not chosen.
    final noBrand = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 20, 14),
    ).parseRows(coffee.skip(1).toList());
    expect(noBrand.merchant, isNot(startsWith('Santa Clara Mercantil De')));
  });

  test('a choice printed under an item comes with it, without a price', () {
    final items = ItemLineParser.extract(coffee);
    expect([for (final i in items) i.description], [
      'Caramel lced WVhip L Media',
      'Leche Deslactosada MD',
      'Chocolate Frappe Grandę',
    ]);
    expect([for (final i in items) i.amountText], ['100.00', null, '104.00']);
  });

  test('coffee receipt: invoice deadline and the toilet code', () {
    final notes = ReceiptNotes.find(coffee);
    final invoice = notes.firstWhere((n) => n.kind == ReceiptNoteKind.invoice);
    expect(invoice.title, 'Tax invoice (factura): request it within 30 days');
    expect(invoice.detail, contains('Online: https://facturas.example.com/facturacion'));
    expect(invoice.detail, contains('Ask at the till when paying'));
    final toilet = notes.firstWhere((n) => n.kind == ReceiptNoteKind.toilet);
    expect(toilet.title, 'Toilet code: 1234#');
    expect(notes.where((n) => n.kind == ReceiptNoteKind.offer), isEmpty);
  });

  test('fast-food ticket: invoice folio, Wi-Fi, survey offer', () {
    final notes = ReceiptNotes.find(fastFood);
    final invoice = notes.firstWhere((n) => n.kind == ReceiptNoteKind.invoice);
    expect(invoice.title, 'Tax invoice (factura): ask for it when paying');
    expect(invoice.detail, contains('Invoice reference (folio): 0000000000000001'));
    // The privacy notice's address is not the invoice site.
    expect(invoice.detail, isNot(contains('www.example.com.mx')));

    final wifi = notes.firstWhere((n) => n.kind == ReceiptNoteKind.wifi);
    expect(wifi.detail, 'Network: CLIENTES-WIFI\nPassword: Secret123');

    final offer = notes.firstWhere((n) => n.kind == ReceiptNoteKind.offer);
    expect(offer.title, 'Answer the survey for something free next visit');
    expect(offer.detail, 'Online: www.encuesta-example.com');
    expect(offer.printed, contains('Papas Chicas gratis'));
  });

  test('tip included or not', () {
    expect(ReceiptNotes.find(['LA PROPINA NO ESTA INCLUIDA']).single.title,
        'Tip not included in the total');
    expect(ReceiptNotes.find(['Service charge included']).single.title,
        'Tip or service already included');
  });

  test('a discount taken off this bill is not an offer; nothing to say is '
      'nothing said', () {
    expect(ReceiptNotes.find(['DESCUENTO 10% -20.00', 'TOTAL 180.00']), isEmpty);
    expect(ReceiptNotes.find(['TACOS 3 90.00', 'TOTAL 90.00']), isEmpty);
  });
}

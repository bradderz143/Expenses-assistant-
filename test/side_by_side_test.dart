import 'package:expense_assistant/domain/logic/item_area_detector.dart';
import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/ocr_row_assembler.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A card slip and an itemised ticket for the same purchase, photographed
/// side by side (Inbursa slip on the left, vet's ticket on the right).
OcrResult twoReceipts() {
  OcrLine line(String text, double left, double top, double right) =>
      OcrLine(text: text, left: left, top: top, right: right, bottom: top + 24);
  final left = <(String, double, double)>[
    ('INBURSA', 100, 400),
    ('INBURSA', 100, 400),
    ('VENTA', 150, 400),
    ('VETERINARIA EJEMPLO', 100, 400),
    ('CALLE EJEMPLO NO 100 SN', 100, 400),
    ('CIUDAD DE MEXICO CDMX', 100, 400),
    ('CAJA: 2 1000001', 100, 400),
    ('15 NOV 2026', 100, 230),
    ('************0000', 100, 300),
    ('CREDITO/EXTRANJERA', 100, 350),
    ('/MASTERCARD', 100, 250),
    ('OPER. 168  LOTE: 009', 100, 400),
    ('IMPORTE \$ 635.00', 100, 400),
    ('APROBADA AUT.PYL195', 100, 400),
  ];
  final right = <(String, double, double)>[
    ('VETEJEMPLO', 500, 700),
    ('15/11/2026 01:41 PM', 500, 750),
    ('CAJERO: ADMINISTRADOR DE LA TIEN', 460, 780),
    ('TURNO # 1249', 460, 700),
    ('FOLIO: 10001', 460, 700),
    ('CANT. DESCRIPCIONPRECIO IMPORTE', 460, 780),
    ('1 VACUNA \$320.00 \$320.00', 460, 780),
    ('GIARDIA', 500, 600),
    ('1 SIMPARI \$315.00 \$315.00', 460, 780),
    ('CA TRIO', 500, 600),
    ('NO. DE ARTICULOS: 2', 460, 700),
    ('TOTAL: \$635.00', 500, 750),
    ('PAGO CON TARJETA', 480, 720),
  ];
  return OcrResult(text: '', lines: [
    for (var i = 0; i < left.length; i++)
      line(left[i].$1, left[i].$2, 300.0 + i * 40, left[i].$3),
    // The time sits on the same row as the date, as on the slip.
    line('13:44:23', 330, 300.0 + 7 * 40, 400),
    // The ticket starts a little lower, so its rows never line up exactly.
    for (var i = 0; i < right.length; i++)
      line(right[i].$1, right[i].$2, 312.0 + i * 40, right[i].$3),
  ]);
}

void main() {
  test('two receipts side by side are read one after the other', () {
    final rows = OcrRowAssembler.assemble(twoReceipts().lines)
        .map((r) => r.text)
        .toList();
    final slipEnd = rows.indexOf('APROBADA AUT.PYL195');
    final ticketStart = rows.indexOf('VETEJEMPLO');
    expect(slipEnd, lessThan(ticketStart));
    expect(rows, contains('15 NOV 2026  13:44:23')); // not joined to an item
    expect(rows, contains(r'1 VACUNA $320.00 $320.00'));
  });

  test('a price column beside its descriptions is not two receipts', () {
    OcrLine line(String text, double left, double right, int row) => OcrLine(
        text: text, left: left, top: row * 40.0, right: right, bottom: row * 40.0 + 24);
    final rows = OcrRowAssembler.assemble([
      for (var i = 0; i < 8; i++) ...[
        line('2 TACOS AL PASTOR NUMERO $i', 20, 420, i),
        line('${i + 1}0.00', 600, 680, i),
      ],
    ]);
    expect(rows, hasLength(8));
    expect(rows.first.text, '2 TACOS AL PASTOR NUMERO 0  10.00');
  });

  test('items are the ticket\'s, not a date and a vaccine mixed together', () {
    final rows = OcrRowAssembler.assemble(twoReceipts().lines)
        .map((r) => r.text)
        .toList();
    final items = ItemLineParser.extract(rows);
    expect(items.map((i) => i.description), contains('VACUNA'));
    expect(items.map((i) => i.description), contains('SIMPARI'));
    expect(items.where((i) => i.description.contains('NOV')), isEmpty);
  });

  test('a date and time joined to an item row are dropped from it', () {
    final items = ItemLineParser.extract([
      '15 NOV 2026  13:44:23  1 VACUNA \$320.00 \$320.00',
      'TOTAL \$320.00',
    ]);
    expect(items.single.description, 'VACUNA');
    expect(items.single.amountText, '320.00');
  });

  test('the shop, not the bank whose machine printed the slip', () {
    final parsed = ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 16),
    ).parse(twoReceipts());
    expect(parsed.merchant, 'Veterinaria Ejemplo');
    expect(parsed.date, DateTime(2026, 11, 15));
    expect(parsed.amountMinor, 63500);
  });

  test('item area covers the ticket, not the slip beside it', () {
    final area = ItemAreaDetector.detect(twoReceipts().lines)!;
    expect(area.left, greaterThan(400));
  });
}

import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receipts an independent check used to break the shop-name and date
/// rules. Every case here was a wrong result once.
ParsedReceipt parse(List<String> rows) => ReceiptTextParser(
      defaultCurrency: 'MXN',
      clock: () => DateTime(2026, 11, 23, 9),
    ).parseRows(rows);

String? shop(List<String> rows) => parse(rows).merchant?.toLowerCase();

void main() {
  group('rows that are not the shop although they open with a shop word', () {
    test('a branch row under or over the legal name', () {
      expect(
        shop([
          'COMERCIALIZADORA EJEMPLO SA DE CV',
          'TIENDA GUADALAJARA CENTRO',
          'TOTAL 63.00',
        ]),
        'comercializadora ejemplo',
      );
    });

    test('a legal name wrapped over two rows, the trade name below', () {
      expect(
        shop([
          'GRUPO GASTRONOMICO EJEMPLO DE MEXICO',
          'SA DE CV',
          'LA TERRAZA DEL EJEMPLO',
          'TOTAL 305.00',
        ]),
        'la terraza del ejemplo',
      );
      expect(
        shop([
          'HOTELES EJEMPLO DE MEXICO',
          'SA DE CV',
          'RFC XXX010101AB1',
          'HOTEL EJEMPLO REFORMA',
          'TOTAL 2,150.00',
        ]),
        'hotel ejemplo reforma',
      );
    });

    test('the value under a bare label: destination, customer', () {
      expect(
        shop([
          'TRANSPORTES EJEMPLO SA DE CV',
          'DESTINO:',
          'HOTEL EJEMPLO CANCUN',
          r'TOTAL $650.00',
        ]),
        'transportes ejemplo',
      );
      expect(
        shop([
          'OPERADORA EJEMPLO SA DE CV',
          'CLIENTE:',
          'GRUPO CONSULTOR EJEMPLO MEXICO',
          'TOTAL 450.00',
        ]),
        'operadora ejemplo',
      );
    });

    test('a neighbourhood, a bank group', () {
      expect(
        shop([
          'OPERADORA DE ALIMENTOS EJEMPLO SA DE CV',
          'CLUB DE GOLF MEXICO',
          'TOTAL 131.00',
        ]),
        'operadora de alimentos ejemplo',
      );
      expect(
        shop([
          'SANTANDER',
          'GRUPO FINANCIERO SANTANDER MEXICO',
          'TACOS EL EJEMPLO',
          r'TOTAL $186.00',
        ]),
        'tacos el ejemplo',
      );
    });

    test('a hotel named after its town is still the shop', () {
      expect(
        shop(['HOTEL EJEMPLO CANCUN', 'RESTAURANTE', 'TOTAL 950.00']),
        'hotel ejemplo cancun',
      );
      expect(
        shop(['LOBBY BAR', 'HOTEL EJEMPLO CANCUN', 'TOTAL 455.00']),
        'hotel ejemplo cancun',
      );
      expect(
        shop(['ROOM SERVICE', 'HOTEL EJEMPLO MONTERREY', 'TOTAL 455.00']),
        'hotel ejemplo monterrey',
      );
    });
  });

  group('a date, a comma, then the time', () {
    test('with a one-digit hour', () {
      for (final row in [
        'Nov 20, 2026, 8:14 PM',
        '20 nov 2026, 8:14 p. m.',
        'Fecha: 20 nov 2026, 8:14',
        '20 de noviembre de 2026, 8:14',
        'November 20, 2026, 9:05:11 PM',
        '20 nov 2026, 08:14',
      ]) {
        expect(
          parse(['EXAMPLE COFFEE', row, 'Total 4.50']).date,
          DateTime(2026, 11, 20),
          reason: row,
        );
      }
    });

    test('two such dates: the right one, not just the readable one', () {
      expect(
        parse([
          'EXAMPLE INN',
          'Check-in: Nov 18, 2026, 10:30 PM',
          'Check-out: Nov 20, 2026, 7:45 AM',
        ]).date,
        DateTime(2026, 11, 20),
      );
      expect(
        parse([
          'DiDi',
          '20 nov 2026, 7:52 a. m.',
          'Factura emitida: 22 nov 2026, 10:15 a. m.',
        ]).date,
        DateTime(2026, 11, 20),
      );
    });

    test('a price after a year-like number is still no date', () {
      for (final row in ['3 MAR 20,00', '12 MAY 2026,50', '1 MAYONESA 2026,00']) {
        expect(parse(['EJEMPLO', row, 'TOTAL 20.00']).date, isNull, reason: row);
      }
    });

    test('the delivery date is not the purchase date', () {
      expect(
        parse([
          'EXAMPLE STORE',
          'Order placed Nov 20, 2026',
          'Delivery date: Nov 22, 2026',
          r'Total $45.00',
        ]).date,
        DateTime(2026, 11, 20),
      );
    });
  });
}

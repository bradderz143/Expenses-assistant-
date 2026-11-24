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

  group('round three: the shop', () {
    test('the name under a label that says who sells', () {
      for (final label in [
        'Emisor:',
        'Vendedor:',
        'Sold by:',
        'RAZON SOCIAL:',
        'VENDIDO POR:',
        'EMPRESA:',
        'Comercio:',
      ]) {
        expect(
          shop([
            label,
            'CAFE EJEMPLO, S.A.',
            '20/11/2026',
            '1 CAPUCCINO 24.00',
            'TOTAL 24.00',
          ]),
          'cafe ejemplo',
          reason: label,
        );
      }
    });

    test('a slogan or branch under a legal suffix on its own row', () {
      expect(
        shop(['FERRETERIA EJEMPLO', 'S.A. DE C.V.', 'TODO PARA LA CONSTRUCCION']),
        'ferreteria ejemplo',
      );
      expect(
        shop(['FARMACIA EJEMPLO', 'S.A. DE C.V.', 'PLAZA LAS AMERICAS']),
        'farmacia ejemplo',
      );
    });

    test('a hotel printed under the company is where the ride goes', () {
      expect(
        shop(['TRANSFERS EJEMPLO SA DE CV', 'HOTEL EJEMPLO CANCUN']),
        'transfers ejemplo',
      );
    });

    test('the kind of place on one row, its name with a town on the next',
        () {
      expect(
        shop([
          'RESTAURANTE',
          'LA EJEMPLO DE OAXACA',
          '19/11/2026',
          '1 MOLE NEGRO 185.00',
          'TOTAL 185.00',
        ]),
        'la ejemplo de oaxaca',
      );
      expect(
        shop(['CASA EJEMPLO OAXACA', 'RESTAURANTE', 'TOTAL 260.00']),
        'casa ejemplo oaxaca',
      );
    });

    test('a wine shop is not a car hire firm', () {
      expect(shop(['LA EUROPEA', 'TOTAL 1,312.00']), 'la europea');
    });
  });

  group('round three: the amount paid', () {
    test('a discount under the subtotal: the total is the smaller figure', () {
      expect(
        parse([
          'TIENDA EJEMPLO',
          r'Subtotal $2,297.00',
          r'Descuento -$229.70',
          r'Total $2,067.30',
        ]).amountMinor,
        206730,
      );
      expect(
        parse([
          'TIENDA EJEMPLO',
          'SUBTOTAL 2,297.00',
          'DESCUENTO 229.70',
          'TOTAL 2,067.30',
        ]).amountMinor,
        206730,
      );
      // A tip misread as the total is still refused.
      expect(
        parse(['FONDA', 'SUBTOTAL 475.00', 'PROPINA 71.25', 'TOTAL 71.25'])
            .amountMinor,
        47500,
      );
    });

    test('a year, a comma and the time are not money', () {
      final p = parse([
        'Rappi',
        r'Subtotal MX$506.00',
        r'Promoción -MX$151.80',
        r'Total MX$412.50',
        '19 nov 2026, 21:14',
      ]);
      expect(p.amountMinor, 41250);
      expect(p.date, DateTime(2026, 11, 19));
    });

    test('a price for each hour is not what was paid', () {
      expect(
        parse([
          'ESTACIONAMIENTO EJEMPLO',
          r'TARIFA: $20.00 X HORA',
          r'IMPORTE: $60.00',
        ]).amountMinor,
        6000,
      );
    });

    test('how many travel is not the shop', () {
      expect(
        shop([
          'TRANSFERS EJEMPLO SA DE CV',
          'RFC XXX010101AB1',
          'RECIBO DE TRASLADO',
          '14/11/2026 15:40',
          'HOTEL EJEMPLO CANCUN',
          '2 PASAJEROS',
          r'TRASLADO PRIVADO SENCILLO $650.00',
          r'TOTAL $650.00',
        ]),
        'transfers ejemplo',
      );
    });
  });
}

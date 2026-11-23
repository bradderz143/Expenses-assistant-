import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Header fields (date, time, merchant) across the receipts a traveller
/// meets in Mexico, Central America, Venezuela, Colombia, the US and the UK.
/// Every receipt is made up (generic names, numbers and tax IDs) but laid
/// out the way real tills, terminals and e-mail receipts print.
void main() {
  // The moment of the scan: Monday 23 November 2026, 09:00.
  DateTime clock() => DateTime(2026, 11, 23, 9);
  final day = DateTime(2026, 11, 23);

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

  /// The rows under the header of an ordinary till ticket.
  const body = [
    'CANT DESCRIPCION IMPORTE',
    '1 CAFE AMERICANO 45.00',
    '1 PAN DULCE 25.00',
    'TOTAL 70.00',
  ];

  /// A ticket whose only date is [row].
  List<String> dated(String row) => [
        'RESTAURANTE EJEMPLO',
        'AV. EJEMPLO 100 COL. CENTRO',
        row,
        ...body,
      ];

  void expectDate(ParsedReceipt p, DateTime? date, {bool flagged = false}) {
    expect(p.date, date);
    if (date != null) expect(p.dateDoubtful, flagged);
  }

  group('date formats', () {
    for (final row in [
      '23/11/2026',
      '23-11-26',
      '23.11.2026',
      '23.11.26',
      '2026-11-23',
      '2026/11/23 09:02',
      '2026-11-23T09:02:11',
      '23NOV2026',
      '23NOV26 09:02',
      '23/NOV/2026',
      '23/Nov/26',
      '23-nov.-2026',
      '23 NOV 2026 09:02 HRS',
      'NOV 23, 2026',
      'Nov 23, 2026 9:02 AM',
      'NOV-23-2026',
      "Nov 23 '26",
      "23 Nov'26",
      '23 de noviembre de 2026',
      '23 de nov. de 2026',
      'Lunes, 23 de Noviembre del 2026',
      'lun, 23 nov 2026',
      'Mon 23 Nov 2026',
      'November 23, 2026',
      'NOVIEMBRE 23, 2026',
      'Noviembre 23 de 2026',
      '23 November 2026',
      '23rd November 2026',
      'Seg, 23 de novembro de 2026',
      '11/23/2026',
      '11-23-26 09:02',
      '23/11/202609:02',
      '23/11/26 09:02:11',
      'NOV 23, 26 09:02',
    ]) {
      test(row, () => expectDate(parse(dated(row)), day));
    }

    test('a long month name before the day', () {
      expectDate(
        parse([
          'HOTEL EJEMPLO',
          'Septiembre 14, 2026',
          'TOTAL 1,200.00',
        ]),
        DateTime(2026, 9, 14),
      );
    });
  });

  group('date labels', () {
    for (final row in [
      'FECHA: 23/11/2026',
      'FECHA:23/11/2026HORA:09:02',
      'Fecha de emision: 23/11/2026 09:02',
      'FECHA DE EMISION: 23-nov-2026 09:02',
      'Fecha y hora de certificacion: 23-nov-2026 09:02:11',
      'Fecha y hora de generacion: 2026-11-23 09:02:11',
      'Emitido: 23/11/2026',
      'Date: 23/11/2026',
      'DATE 11/23/2026 TIME 09:02',
      'Data: 23/11/2026',
      'Fecha de consumo: 23/11/2026',
      'Fecha de operacion: 23/11/2026',
      'FECHA/HORA: 23/11/2026 09:02',
      'F.EMISION 23/11/2026',
      'Fecha Venta: 23/11/2026',
    ]) {
      test(row, () => expectDate(parse(dated(row)), day));
    }

    test('the day of consumption, not the day it was printed', () {
      expectDate(
        parse([
          'HOTEL EJEMPLO REFORMA',
          'RESTAURANTE LA TERRAZA',
          'Fecha de impresion: 23/11/2026 08:10',
          'Fecha de consumo: 22/11/2026',
          'Habitacion: 512',
          '2 DESAYUNO BUFFET 590.00',
          'TOTAL 590.00',
        ]),
        DateTime(2026, 11, 22),
      );
      // A printing time is still the date when it is the only one.
      expectDate(
        parse(['TAQUERIA EJEMPLO', 'IMPRESO: 23/11/2026 09:02', ...body]),
        day,
      );
    });
  });

  group('dates that are not the purchase', () {
    test('card expiry', () {
      for (final row in [
        'TARJETA ************1234 EXP 11/28',
        'VENCE: 11/28',
        'EXP. DATE 11/2028',
        'VISA ****1234 VTO 11/28',
      ]) {
        expectDate(
          parse(['TIENDA EJEMPLO', '23/11/2026 09:02', ...body, row]),
          day,
        );
        expectDate(parse(['TIENDA EJEMPLO', ...body, row]), null);
      }
    });

    test('promotion, coupon and returns dates', () {
      for (final row in [
        'PROMOCION VALIDA DEL 01/11/2026 AL 30/11/2026',
        'CUPON VALIDO HASTA EL 15/12/2026',
        'VIGENCIA: 01/11/2026 - 30/11/2026',
        'CAMBIOS Y DEVOLUCIONES HASTA EL 23/12/2026',
        'Promocion vigente del 1 al 22 de noviembre de 2026',
        'Oferta valida al 22/11/2026',
      ]) {
        expectDate(
          parse(['TIENDA EJEMPLO', '23/11/2026 09:02', ...body, row]),
          day,
        );
        expectDate(
          parse(['TIENDA EJEMPLO', row, 'FECHA 23/11/2026', ...body]),
          day,
        );
      }
    });

    test('the tax authority\'s limit and resolution dates', () {
      // Honduras and Venezuela print the last day the numbering may be used.
      expectDate(
        parse([
          'INVERSIONES EJEMPLO S. DE R.L.',
          'RTN: 08011900000000',
          'CAI: 000000-000000-000000-000000-000000-00',
          'Rango autorizado: 000-001-01-00000001 al 000-001-01-00050000',
          'Fecha limite de emision: 15/08/2027',
          'Factura: 000-001-01-00012345',
          'Fecha: 23/11/2026 09:02',
          ...body,
        ], currency: 'HNL'),
        day,
      );
      // Central American tickets quote the resolution that authorised them.
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO, S.A. DE C.V.',
          'NIT: 0614-010101-101-1 NRC: 100000-1',
          'RESOLUCION No. 15041-RES-CR-12345-2019 DE FECHA 12/03/2019',
          'TIQUETE No. 0012345',
          '23/11/2026 09:02',
          ...body,
        ], currency: 'USD'),
        day,
      );
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO, S.A. DE C.V.',
          'NIT: 0614-010101-101-1 NRC: 100000-1',
          'SEGUN RESOLUCION No. 15041-RES-CR-12345-2019',
          'DE FECHA 12/03/2019',
          'TIQUETE No. 0012345',
          '23/11/2026 09:02',
          ...body,
        ], currency: 'USD'),
        day,
      );
      // Colombia: the DIAN resolution, often less than a year old.
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO S.A.S.',
          'NIT 900.000.000-1',
          'Res. DIAN No. 18764000000001 de 2026/02/10',
          'Prefijo POS del 1 al 500000',
          'Factura de venta POS No. 123456',
          '2026/11/21 13:05',
          ...body,
        ], currency: 'COP'),
        DateTime(2026, 11, 21),
      );
      expectDate(
        parse([
          'RESTAURANTE EJEMPLO S.A.S.',
          'NIT 900.000.000-1',
          'Autorizacion numeracion de facturacion 18764000000001',
          'Fecha 2026-02-10 Vigencia 24 meses',
          'Factura de venta POS No. 123456',
          'Fecha: 2026-11-21 Hora: 13:05',
          ...body,
        ], currency: 'COP'),
        DateTime(2026, 11, 21),
      );
    });

    test('a membership date', () {
      expectDate(
        parse([
          'CLUB DE PRECIOS EJEMPLO',
          '23/11/2026 09:02',
          ...body,
          'SOCIO DESDE: 12/05/2019',
        ]),
        day,
      );
    });

    test('a street named after a date, with no "Av." in front', () {
      for (final street in [
        '5 DE MAYO 12 CENTRO',
        '16 DE SEPTIEMBRE 15, CENTRO HISTORICO',
        'CALLE 5 DE FEBRERO 20',
        '20 DE NOVIEMBRE 25 LOCAL 3',
      ]) {
        expectDate(
          parse(['RESTAURANTE EJEMPLO', street, '23/11/2026 09:02', ...body]),
          day,
        );
        expectDate(parse(['RESTAURANTE EJEMPLO', street, ...body]), null);
      }
    });

    test('a hotel stay: the day of the bill, not the arrival', () {
      expectDate(
        parse([
          'HOTEL EJEMPLO REFORMA',
          'Huesped: JUAN PEREZ',
          'Habitacion: 512 Folio: 100001',
          'Llegada: 20/11/2026 Salida: 23/11/2026',
          'Fecha: 23/11/2026 08:41',
          'HOSPEDAJE 3 NOCHES 7,500.00',
          'TOTAL 7,500.00',
        ]),
        day,
      );
      expectDate(
        parse([
          'HOTEL EJEMPLO REFORMA',
          'Guest: JUAN PEREZ',
          'Room: 512 Folio: 100001',
          'Arrival: 20/11/2026 Departure: 23/11/2026',
          '23/11/2026 08:41 Cashier: 12',
          'ROOM CHARGE 3 NIGHTS 7,500.00',
          'TOTAL 7,500.00',
        ]),
        day,
      );
    });

    test('a hotel folio of dated charges: the day of departure', () {
      expectDate(
        parse([
          'HOTEL EJEMPLO REFORMA',
          'Huesped: JUAN PEREZ',
          'Habitacion: 512 Folio: 100001',
          'Llegada: 20/11/26 Salida: 23/11/26',
          'Fecha Descripcion Cargos Abonos',
          '20/11/26 HABITACION 2,500.00',
          '21/11/26 HABITACION 2,500.00',
          '22/11/26 HABITACION 2,500.00',
          '23/11/26 VISA ****1234 7,500.00',
          'TOTAL 7,500.00',
          'SALDO 0.00',
        ]),
        day,
      );
    });

    test('a number that only looks like a date', () {
      for (final row in [
        'FOLIO: 231120260001',
        'FACTURA: 000-001-01-00012345',
        'TEL: 55.12.34.56',
        'NIT: 0614-010101-101-1',
        'Permiso CRE: PL/1234/EXP/ES/2015',
        'AUTORIZACION: A1B2C3D4-1234-5678-9ABC-DEF012345678',
        'Sistema POS v2.11.26',
        'TICKET 2026112300045',
      ]) {
        expectDate(parse(['TIENDA EJEMPLO', row, ...body]), null);
      }
    });
  });

  group('day or month first', () {
    test('a reading in the future is the other order, to be checked', () {
      // A US-made till in Mexico printing 12 November as 11/12.
      final p = parse(dated('11/12/2026 14:05'));
      expect(p.date, DateTime(2026, 11, 12));
      expect(p.dateDoubtful, isTrue);
    });

    test('a reading months old against one days old: the recent one, '
        'to be checked', () {
      final p = parse(dated('11/05/26 14:05'));
      expect(p.date, DateTime(2026, 11, 5));
      expect(p.dateDoubtful, isTrue);
    });

    test('the usual order is kept when it gives the recent day', () {
      expectDate(parse(dated('05/11/2026 14:05')), DateTime(2026, 11, 5));
      expectDate(parse(dated('11/11/2026')), DateTime(2026, 11, 11));
      expectDate(parse(dated('03/04/2026')), DateTime(2026, 4, 3));
      expectDate(
        parse(dated('11/05/2026'), currency: 'USD', monthFirst: true),
        DateTime(2026, 11, 5),
      );
    });

    test('another date on the receipt shows the order', () {
      // The coupon's last day can only be month first.
      expectDate(
        parse([
          ...dated('11/05/2026 14:05'),
          'CUPON VALIDO HASTA 12/31/2026',
        ]),
        DateTime(2026, 11, 5),
      );
      // The same day printed with the month's name.
      expectDate(
        parse([
          'CAFE EJEMPLO',
          "Nov05'26 03:12PM",
          ...body,
          'Fecha 11/05/2026',
        ]),
        DateTime(2026, 11, 5),
      );
      expectDate(
        parse([
          'CAFE EJEMPLO',
          'Fecha 11/05/2026',
          ...body,
          "Nov05'26 03:12PM",
        ]),
        DateTime(2026, 11, 5),
      );
    });
  });

  group('damaged dates', () {
    for (final row in [
      '23/11/2O26 09:02',
      '23/1l/2026 09:02',
      'Z3/11/2026',
      '23/I1/2026',
      '23 /11 /2026',
      '23/ 11/ 2026',
      '23/11/20 26',
      '23-11-2O26',
      'FECHA 2O26-11-23',
      '23|11|2026 09:02',
      '23/NOV/2O26',
      '23 N0V 2026',
      "23 Nov`26 08:59 AM",
      '23 Nov 26 08:59 AM',
      'FECHA23/11/2026',
    ]) {
      test(row, () => expectDate(parse(dated(row)), day));
    }
  });

  group('time', () {
    String? timeOf(List<String> rows) => parse(rows).time;

    test('beside the date, in the ways tills print it', () {
      expect(timeOf(dated('FECHA: 23/11/2026 HORA: 09:02')), '09:02');
      expect(timeOf(dated('23/11/2026 02:35:10 p. m.')), '14:35');
      expect(timeOf(dated('23/11/2026 9:02 PM')), '21:02');
      expect(timeOf(dated('23/11/2026 12:05 AM')), '00:05');
      expect(timeOf(dated("23 Nov'26 08:59 AM")), '08:59');
      expect(timeOf(dated('23/11/202609:02')), '09:02');
      expect(timeOf(dated('2026-11-23T09:02:11')), '09:02');
    });

    test('opening hours are not the time of purchase', () {
      expect(
        timeOf([
          'CAFE EJEMPLO',
          'HORARIO: LUN A DOM 07:00 A 23:00',
          'FECHA: 23/11/2026 14:35',
          ...body,
        ]),
        '14:35',
      );
      expect(
        timeOf([
          'CAFE EJEMPLO',
          'Abierto de 7:00 a 23:00 hrs',
          '23/11/2026 14:35',
          ...body,
        ]),
        '14:35',
      );
      expect(
        timeOf(['CAFE EJEMPLO', 'HORARIO: 07:00 - 23:00', ...body]),
        isNull,
      );
    });
  });

  group('merchant: the name on the sign', () {
    void expectMerchant(List<String> head, String? name) =>
        expect(parse([...head, ...body]).merchant, name, reason: '$head');

    test('convenience stores and supermarkets', () {
      expectMerchant([
        'OXXO',
        'CADENA COMERCIAL OXXO SA DE CV',
        'RFC XXX010101AB1',
        'TIENDA 50XYZ EJEMPLO',
        '23/11/2026 09:02',
      ], 'OXXO');
      expectMerchant([
        'WAL-MART',
        'NUEVA WAL MART DE MEXICO S DE RL DE CV',
        'RFC XXX010101AB1',
        'UNIDAD 1234 EJEMPLO',
      ], 'Walmart');
      expectMerchant([
        '7-ELEVEN',
        '7-ELEVEN MEXICO SA DE CV',
        'TIENDA 1234',
      ], '7-Eleven');
      expectMerchant([
        'TIENDAS CHEDRAUI SA DE CV',
        'RFC XXX010101AB1',
        'SUC. 123 EJEMPLO',
      ], 'Chedraui');
      expectMerchant(['SORIANA HIPER', 'TIENDAS SORIANA SA DE CV'], 'Soriana Hiper');
      expectMerchant(['LA COMER', 'COMERCIAL CITY FRESKO S DE RL DE CV'], 'La Comer');
    });

    test('fuel stations', () {
      expectMerchant([
        'SERVICIO EJEMPLO SA DE CV',
        'ESTACION DE SERVICIO 1234',
        'PEMEX',
        'RFC XXX010101AB1',
        'Permiso CRE: PL/1234/EXP/ES/2015',
      ], 'Pemex');
      expectMerchant([
        'GASOLINERA EJEMPLO SA DE CV',
        'E.S. 1234',
        'RFC XXX010101AB1',
      ], 'Gasolinera Ejemplo');
      expectMerchant(['SHELL', 'COMBUSTIBLES EJEMPLO, S.A.', 'NIT: 123456-7'], 'Shell');
      expectMerchant(['PUMA ENERGY', 'ESTACION EJEMPLO', 'NIT: 123456-7'], 'Puma Energy');
      expectMerchant(['TEXACO', 'SERVICENTRO EJEMPLO'], 'Texaco');
    });

    test('pharmacies', () {
      expectMerchant([
        'FARMACIAS GUADALAJARA SA DE CV',
        'RFC XXX010101AB1',
      ], 'Farmacias Guadalajara');
      expectMerchant([
        'FARMACIA GUADALAJARA',
        'SUC. 123 EJEMPLO',
      ], 'Farmacias Guadalajara');
      expectMerchant(['FARMACIAS DEL AHORRO', 'SUC. EJEMPLO'], 'Farmacias del Ahorro');
      expectMerchant(['FARMACIAS SIMILARES', 'SUC. EJEMPLO'], 'Farmacias Similares');
    });

    test('restaurants and cafes: brand above or below the company', () {
      expectMerchant([
        'POLLO CAMPERO',
        'RESTAURANTES EJEMPLO, S.A.',
        'NIT: 123456-7',
        '6A AVENIDA 12-34 ZONA 10',
      ], 'Pollo Campero');
      expectMerchant([
        'OPERADORA DE RESTAURANTES EJEMPLO SA DE CV',
        'RFC XXX010101AB1',
        'AV. EJEMPLO 100 COL. CENTRO',
        'VIPS REFORMA',
      ], 'Vips Reforma');
      expectMerchant([
        'OPERADORA DE RESTAURANTES EJEMPLO SA DE CV',
        'RFC XXX010101AB1',
        'AV. EJEMPLO 100 COL. CENTRO',
        'LA CASA DEL EJEMPLO',
        'SUCURSAL CENTRO',
      ], 'La Casa del Ejemplo');
      expectMerchant(["McDONALD'S", 'ARCOS EJEMPLO SA DE CV'], "McDonald's");
      expectMerchant(["Mc Donald's", 'Restaurante 1234'], "McDonald's");
      expectMerchant(['SUBWAY', 'Restaurante #12345'], 'Subway');
      expectMerchant(["CHILI'S", 'GRUPO EJEMPLO SA DE CV'], "Chili's");
      expectMerchant(['TOKS', 'RESTAURANTES TOKS SA DE CV'], 'Toks');
      expectMerchant(['TACO BELL', 'Store 1234'], 'Taco Bell');
      expectMerchant(["WENDY'S", 'Restaurante 1234'], "Wendy's");
    });

    test('hotels, airlines, buses, tolls, cinemas, parking', () {
      expectMerchant([
        'HOTEL EJEMPLO REFORMA',
        'OPERADORA HOTELERA EJEMPLO SA DE CV',
        'RFC XXX010101AB1',
        'HUESPED: JUAN PEREZ',
        'HABITACION: 512',
      ], 'Hotel Ejemplo Reforma');
      expectMerchant([
        'AEROMEXICO',
        'AEROVIAS DE MEXICO SA DE CV',
        'RECIBO DE BOLETO ELECTRONICO',
        'PASAJERO: PEREZ/JUAN',
      ], 'Aeroméxico');
      expectMerchant(['ADO', 'AUTOBUSES DE ORIENTE ADO SA DE CV'], 'ADO');
      expectMerchant([
        'CAPUFE',
        'CAMINOS Y PUENTES FEDERALES',
        'PLAZA DE COBRO 001 EJEMPLO',
        'CARRIL 05 TURNO 2',
      ], 'CAPUFE');
      expectMerchant(['CINEPOLIS', 'CINEPOLIS DE MEXICO SA DE CV'], 'Cinépolis');
      expectMerchant([
        'ESTACIONAMIENTO EJEMPLO',
        'BOLETO 123456',
        'ENTRADA: 23/11/2026 08:15',
        'SALIDA: 23/11/2026 10:40',
      ], 'Estacionamiento Ejemplo');
    });

    test('department stores, the US and the UK', () {
      expectMerchant(['LIVERPOOL', 'DISTRIBUIDORA LIVERPOOL SA DE CV'], 'Liverpool');
      expectMerchant(['WALGREENS', '#1234 100 EXAMPLE ST', 'HOUSTON, TX 77002'], 'Walgreens');
      expectMerchant(['TARGET', 'Houston Central - 713-000-0000'], 'Target');
      expectMerchant(['TESCO', 'Express', 'VAT NO. 000 0000 00'], 'Tesco');
      expectMerchant(['Pret', '10 Example Street', 'London W1A 1AA'], 'Pret');
      expect(
        parse(['CVS/pharmacy', '100 EXAMPLE AVE', 'MIAMI, FL 33101', ...body])
            .merchant,
        startsWith('CVS'),
      );
    });

    test('a brand name read with a letter or two wrong', () {
      expectMerchant(['0XX0', 'CADENA COMERCIAL 0XX0 SA DE CV'], 'OXXO');
      expectMerchant(['BURGER K1NG', 'Restaurante 1234'], 'Burger King');
      expectMerchant(['P0LLO CAMPER0', 'NIT: 123456-7'], 'Pollo Campero');
      expectMerchant(['CINEP0LIS', 'Complejo 123'], 'Cinépolis');
      expectMerchant(['WALGREEMS', '#1234 100 EXAMPLE ST'], 'Walgreens');
      expectMerchant(['CHEDRAU1', 'SUC. 123'], 'Chedraui');
    });

    test('app receipts name the app', () {
      expect(
        parse([
          'DiDi',
          'Gracias por viajar con DiDi, Juan',
          '23 de noviembre de 2026',
          r'Total MX$85.00',
          r'Tarifa del viaje MX$85.00',
        ]).merchant,
        'DiDi',
      );
      expect(
        parse([
          'Rappi',
          'Hola Juan, tu pedido fue entregado',
          'Restaurante Ejemplo',
          '23 nov 2026 14:02',
          r'Total $245.00',
        ]).merchant,
        'Rappi',
      );
      expect(
        parse([
          'Uber Eats',
          'Gracias por tu pedido, Juan',
          r'Total MX$245.00',
          '23 de noviembre de 2026',
        ]).merchant,
        'Uber Eats',
      );
    });

    test('a brand word inside something else is not the merchant', () {
      expectMerchant(
          ['TAQUERIA EJEMPLO', '23/11/2026', '2 HARD SHELL TACO 90.00'],
          'Taqueria Ejemplo');
      expectMerchant(
          ['CAFE EJEMPLO', 'BARISTA: ANA', '23/11/2026 09:02'], 'Cafe Ejemplo');
      expectMerchant(
          ['PANADERIA EJEMPLO', 'AV. SAN MARTIN 123, CENTRO'], 'Panaderia Ejemplo');
      expectMerchant(
          ['TIENDA EJEMPLO', 'PAG ADO CON TARJETA', 'COMBO UNO 99.00'],
          'Tienda Ejemplo');
      expectMerchant(
          ['THE EXAMPLE ARMS', '1 LIVERPOOL STREET', 'LONDON EC2M 7PY'],
          'The Example Arms');
      expectMerchant(
          ['RESTAURANTE EJEMPLO', 'SUBWAY STATION 12 LOCAL 3'], 'Restaurante Ejemplo');
    });
  });

  group('merchant: card slips start with the bank', () {
    for (final bank in [
      'BBVA',
      'BANORTE',
      'SANTANDER',
      'GETNET',
      'CLIP',
      'VISANET',
      'VISANET GUATEMALA',
      'BAC CREDOMATIC',
      'CREDOMATIC',
      'BANRURAL',
      'BANCO INDUSTRIAL',
      'BANCO AGRICOLA',
      'BANCO DE VENEZUELA',
      'BANCOLOMBIA',
      'AMERICAN EXPRESS',
      'SERFINSA',
      'MERCADO PAGO',
    ]) {
      test(bank, () {
        expect(
          parse([
            bank,
            'RESTAURANTE EJEMPLO',
            'AV EJEMPLO 100 CENTRO',
            'VENTA',
            'TARJETA: ************1234',
            '23/11/2026 09:02',
            'TOTAL 350.00',
            'APROBADA 123456',
          ]).merchant,
          'Restaurante Ejemplo',
        );
        // The bank alone names no shop.
        expect(
          parse([
            bank,
            'VENTA',
            'TARJETA: ************1234',
            '23/11/2026 09:02',
            'TOTAL 350.00',
          ]).merchant,
          isNull,
        );
      });
    }

    test('the shop named on a labelled row', () {
      expect(
        parse([
          'GETNET',
          'COMERCIO: TACOS EJEMPLO',
          'AFILIACION: 1000001',
          'VENTA',
          'TOTAL 120.00',
        ]).merchant,
        'Tacos Ejemplo',
      );
      expect(
        parse([
          'FACTURA',
          'NOMBRE COMERCIAL: CAFE EJEMPLO',
          'NIT: 1234567-8',
          'TOTAL Q43.00',
        ], currency: 'GTQ').merchant,
        'Cafe Ejemplo',
      );
    });
  });

  group('merchant: nothing printed is a name', () {
    void expectNone(List<String> head) =>
        expect(parse([...head, ...body]).merchant, isNull, reason: '$head');

    /// What is left at the top when the logo was not read.
    const noise = [
      'AV. EJEMPLO 100 COL. CENTRO',
      'C.P. 06000 CIUDAD DE MEXICO',
      'RFC XXX010101AB1',
      'FOLIO: 12345',
      'FECHA: 23/11/2026 09:02',
    ];

    for (final title in [
      'TICKET DE VENTA',
      'NOTA DE VENTA',
      'FACTURA',
      'FACTURA ELECTRONICA',
      'COPIA CLIENTE',
      'COMPROBANTE DE PAGO',
      'DOCUMENTO TRIBUTARIO ELECTRONICO',
      'DOCUMENTO NO FISCAL',
      'RECIBO DE PAGO',
      'PRE-CUENTA',
      'VOUCHER',
      'REIMPRESION',
      'CONSUMIDOR FINAL',
      'PUBLICO EN GENERAL',
      'SALES RECEIPT',
      'TAX INVOICE',
      'CUSTOMER COPY',
      'MERCHANT COPY',
      'VAT RECEIPT',
      'GUEST CHECK',
      'PARA LLEVAR',
      'PEDIDO 45',
    ]) {
      test('a document title: $title', () => expectNone([title, ...noise]));
    }

    for (final row in [
      'LE ATENDIO: MARIA',
      'ATENDIO JUAN',
      'VENDEDOR: 12 JUAN',
      'CAJERO: MARIA',
      'MESERO JUAN',
      'Server: Mike',
      'Guests: 2',
      'CLIENTE: JUAN PEREZ',
      'TITULAR: JUAN PEREZ',
      'MESA 4 PERSONAS 2',
      'TURNO: MATUTINO',
    ]) {
      test('staff, customer or table: $row', () => expectNone([row, ...noise]));
    }

    for (final row in [
      'PERSONA MORAL REGIMEN GENERAL DE LEY',
      'REGIMEN SIMPLIFICADO DE CONFIANZA',
      'SUJETO A PAGOS TRIMESTRALES ISR',
      'AGENTE DE RETENCION DEL IVA',
      'CONTRIBUYENTE FORMAL',
      'RESPONSABLE DE IVA',
      'PEQUENO CONTRIBUYENTE',
      'NO SOMOS GRANDES CONTRIBUYENTES',
    ]) {
      test('a tax regime: $row', () => expectNone([row, ...noise]));
    }

    for (final row in [
      '6A AVENIDA 12-34 ZONA 10',
      'ZONA 10, CIUDAD DE GUATEMALA',
      'GUATEMALA, GUATEMALA',
      'DIAGONAL 6 10-01 ZONA 10',
      'KM 16.5 CARRETERA A EL SALVADOR',
      'CENTRO COMERCIAL EJEMPLO LOCAL 12',
      'PLAZA EJEMPLO LOCAL 23 PB',
      '1234 EXAMPLE ST',
      'HOUSTON, TX 77002',
      '10 EXAMPLE STREET',
      'LONDON W1A 1AA',
      'VAT NUMBER: GB 000 0000 00',
      'ZAPOPAN, JALISCO',
      'TERMINAL 2 AEROPUERTO INTERNACIONAL',
    ]) {
      test('an address: $row', () => expectNone([row, 'RFC XXX010101AB1']));
    }

    for (final row in [
      'TU OPINION NOS IMPORTA',
      'CUENTANOS TU EXPERIENCIA',
      'Tell us about your visit',
      'GRACIAS POR SU PREFERENCIA',
      '¡BIENVENIDOS!',
      'CONSERVE SU TICKET',
      'ESTE NO ES UN COMPROBANTE FISCAL',
    ]) {
      test('a greeting or request: $row', () => expectNone([row, ...noise]));
    }

    test('items are not a name when the photo starts at them', () {
      expect(
        parse([
          '1 CAFE AMERICANO 45.00',
          '1 PAN DULCE 25.00',
          'TOTAL 70.00',
          'EFECTIVO 100.00',
        ]).merchant,
        isNull,
      );
      expect(
        parse([
          'CODIGO DESCRIPCION PRECIO',
          'PAN DULCE 25.00',
          r'REFRESCO $18.00',
          'TOTAL 43.00',
        ]).merchant,
        isNull,
      );
    });
  });

  group('merchant: the web address when nothing else names the place', () {
    const top = [
      'TICKET DE VENTA',
      'AV. EJEMPLO 100 COL. CENTRO',
      'C.P. 06000 CIUDAD DE MEXICO',
      'FOLIO: 12345',
      'FECHA: 23/11/2026 09:02',
    ];
    String? merchantWith(List<String> tail) =>
        parse([...top, ...body, ...tail]).merchant;

    test('the shop\'s own site or mailbox', () {
      expect(merchantWith(['GRACIAS POR SU COMPRA', 'www.cafe-ejemplo.com.mx']),
          'Cafe Ejemplo');
      expect(merchantWith(['Facturacion: facturas@cafe-ejemplo.com.mx']),
          'Cafe Ejemplo');
      expect(merchantWith(['https://www.cafe-ejemplo.com/facturacion']),
          'Cafe Ejemplo');
    });

    test('never a payment, invoicing, tax, survey, mail or social site', () {
      for (final row in [
        'www.clip.mx',
        'Paga con www.mercadopago.com.mx',
        'Verifica tu factura en www.sat.gob.mx',
        'https://portal.sat.gob.gt/portal/',
        'Factura en: www.facturacion-ejemplo.com',
        'Contesta en www.encuesta-ejemplo.com',
        'cafeejemplo@gmail.com',
        'www.facebook.com/cafeejemplo',
        'Sistema: www.softrestaurant.com.mx',
        'Certificador: www.infile.com.gt',
      ]) {
        expect(merchantWith([row]), isNull, reason: row);
      }
    });

    test('a name printed at the top is kept over the address', () {
      expect(
        parse([
          'OPERADORA EJEMPLO SA DE CV',
          'RFC XXX010101AB1',
          ...body,
          'www.cafe-ejemplo.com.mx',
        ]).merchant,
        'Operadora Ejemplo',
      );
    });
  });

  group('whole receipts', () {
    test('Guatemalan FEL factura', () {
      final p = parse([
        'CAFE EJEMPLO, SOCIEDAD ANONIMA',
        'NIT: 1234567-8',
        '6A AVENIDA 12-34 ZONA 10, GUATEMALA',
        'FACTURA',
        'DOCUMENTO TRIBUTARIO ELECTRONICO',
        'SERIE: A1B2C3D4 NUMERO: 1234567890',
        'NUMERO DE AUTORIZACION:',
        'A1B2C3D4-1234-5678-9ABC-DEF012345678',
        'FECHA DE EMISION: 23/11/2026 08:41',
        'NIT: CF',
        'NOMBRE: CONSUMIDOR FINAL',
        'CANT DESCRIPCION TOTAL',
        '1 CAPUCCINO Q25.00',
        '1 CROISSANT Q18.00',
        'TOTAL Q43.00',
        'SUJETO A PAGOS TRIMESTRALES ISR',
        'CERTIFICADOR: INFILE, S.A. NIT: 12521337',
        'FECHA DE CERTIFICACION: 23/11/2026 08:41:15',
      ], currency: 'GTQ');
      expect(p.merchant, 'Cafe Ejemplo');
      expectDate(p, day);
      expect(p.time, '08:41');
    });

    test('Salvadoran DTE', () {
      final p = parse([
        'DOCUMENTO TRIBUTARIO ELECTRONICO',
        'FACTURA',
        'RESTAURANTE EJEMPLO, S.A. DE C.V.',
        'NIT: 0614-010101-101-1 NRC: 100000-1',
        'Actividad economica: Restaurantes',
        'Codigo de generacion:',
        'A1B2C3D4-1234-5678-9ABC-DEF012345678',
        'Numero de control: DTE-01-M001P001-000000000000001',
        'Fecha y hora de generacion: 23/11/2026 08:41:11',
        'CANT DESCRIPCION TOTAL',
        r'2 PUPUSAS REVUELTAS $2.50',
        r'TOTAL $2.50',
      ], currency: 'USD');
      expect(p.merchant, 'Restaurante Ejemplo');
      expectDate(p, day);
    });

    test('Venezuelan fiscal-printer receipt', () {
      final p = parse([
        'SENIAT',
        'RIF: J-00000000-0',
        'INVERSIONES EJEMPLO 2020, C.A.',
        'AV. FRANCISCO DE MIRANDA, CHACAO',
        'CARACAS',
        'FACTURA',
        'FACTURA: 00012345',
        'FECHA: 23-11-2026 HORA: 08:41',
        'CAFE GRANDE (G) Bs 120,00',
        'TOTAL Bs 120,00',
        'MH Z1B1234567',
      ], currency: 'VES');
      expect(p.merchant, 'Inversiones Ejemplo 2020');
      expectDate(p, day);
      expect(p.time, '08:41');
    });

    test('UK card receipt', () {
      final p = parse([
        'THE EXAMPLE ARMS',
        '10 Example Street',
        'London W1A 1AA',
        'VAT No. 000 0000 00',
        'Table 12 Server: Sam',
        '23/11/2026 08:41',
        '2 Full English 25.00',
        'Total 25.00',
        'VISA DEBIT ************1234',
        'EXP 11/28',
        'AUTH CODE 123456',
        'MERCHANT COPY',
      ], currency: 'GBP');
      expect(p.merchant, 'The Example Arms');
      expectDate(p, day);
    });

    test('US diner receipt', () {
      final p = parse([
        'EXAMPLE DINER',
        '1234 EXAMPLE ST',
        'HOUSTON, TX 77002',
        '(713) 000-0000',
        'Server: Mike Table 5 Guests 2',
        '11/08/2026 6:02 PM',
        'Burger 12.00',
        'Fries 4.00',
        'Total 16.00',
      ], currency: 'USD', monthFirst: true);
      expect(p.merchant, 'Example Diner');
      expectDate(p, DateTime(2026, 11, 8));
      expect(p.time, '18:02');
    });
  });
}

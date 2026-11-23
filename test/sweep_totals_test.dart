import 'package:expense_assistant/domain/logic/amount_in_words.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amount paid and currency, on receipts of the kinds a business traveller
/// collects in Mexico, Guatemala, El Salvador, Venezuela, Colombia, the US
/// and the UK. Every receipt is made up (generic names and numbers) but laid
/// out the way such tills and terminals print, with the damage OCR does.
///
/// The rule for all of them: the amount is what left the traveller's pocket
/// (tip included), in the currency the receipt is in. When the rows do not
/// settle it the result is flagged, never confidently wrong.
void main() {
  ParsedReceipt read(
    List<String> rows, {
    String home = 'MXN',
    bool monthFirst = false,
  }) =>
      ReceiptTextParser(
        defaultCurrency: home,
        monthFirstDates: monthFirst,
        clock: () => DateTime(2026, 11, 23, 9),
      ).parseRows(rows);

  void expectPaid(
    ParsedReceipt p,
    int minor, {
    String? currency,
    bool flagged = false,
  }) {
    expect(p.amountMinor, minor);
    expect(p.amountDoubtful, flagged);
    if (currency != null) expect(p.currency, currency);
  }

  group('shops in Mexico', () {
    test('convenience store, cash and change', () {
      expectPaid(
        read([
          'OXXO',
          'CADENA COMERCIAL OXXO SA DE CV',
          'TIENDA 50XYZ REFORMA',
          '23/11/2026 08:41',
          '1 COCA COLA 600ML 18.00',
          '1 SABRITAS 45G 22.50',
          '1 CAFE ANDATTI 12OZ 27.00',
          r'TOTAL $67.50',
          r'EFECTIVO $100.00',
          r'CAMBIO $32.50',
          'ARTICULOS 3',
        ]),
        6750,
      );
    });

    test('the word TOTAL printed with spaces between its letters', () {
      expectPaid(
        read([
          '7-ELEVEN MEXICO SA DE CV',
          'TDA 1234 INSURGENTES',
          '23/11/2026 07:55',
          '1 CAFE SELECT 16OZ 29.00',
          '1 DONA GLASEADA 16.00',
          '1 AGUA 1L 14.00',
          'S U B T O T A L 59.00',
          'T O T A L 59.00',
          'PAGO EFECTIVO 100.00',
          'SU CAMBIO 41.00',
        ]),
        5900,
      );
      // With nothing else to go on.
      expectPaid(
        read(['PAPELERIA EL LAPIZ', '23/11/2026', 'T O T A L   86.00']),
        8600,
      );
    });

    test('supermarket: items sold and savings are not the total', () {
      expectPaid(
        read([
          'WALMART',
          'NUEVA WAL MART DE MEXICO S DE RL DE CV',
          'TDA#1234 OP#00001234 TE#12 TR#01234',
          '23/11/26 18:22',
          'LECHE LALA 1L 28.50',
          'PAN BIMBO GDE 52.00',
          'JAMON FUD 250G 64.90',
          'DETERGENTE 1KG 39.00',
          'SUBTOTAL 184.40',
          'TOTAL 184.40',
          'EFECTIVO 200.00',
          'CAMBIO 15.60',
          'ARTICULOS VENDIDOS 4',
          'USTED AHORRO 23.50',
        ]),
        18440,
      );
    });

    test('pharmacy: the savings are bigger than the bill', () {
      expectPaid(
        read([
          'FARMACIA DEL AHORRO',
          '23/11/2026 10:15',
          '1 LOSARTAN 50MG 30 TAB 389.00',
          'DESCUENTO -233.40',
          '1 OMEPRAZOL 20MG 14 CAP 152.00',
          'DESCUENTO -91.20',
          r'TOTAL $216.40',
          r'TOTAL AHORRO $324.60',
          r'EFECTIVO $220.00',
          r'CAMBIO $3.60',
        ]),
        21640,
      );
      // The total of the discounts, and of the tax, is not the bill either.
      expectPaid(
        read([
          'FARMACIA SAN PABLO',
          '23/11/2026 10:15',
          '1 VITAMINA C 1G 189.00',
          '1 PROTECTOR SOLAR FPS50 415.00',
          r'TOTAL DESCUENTOS $302.00',
          r'TOTAL IVA $41.66',
          r'TOTAL $302.00',
        ]),
        30200,
      );
    });

    test('points and balances on a loyalty card are not money paid', () {
      expectPaid(
        read([
          'SORIANA',
          '23/11/2026 19:02',
          'ARROZ 1KG 32.90',
          'FRIJOL 1KG 41.50',
          'ACEITE 1L 46.00',
          'TOTAL 120.40',
          'TARJETA DEBITO 120.40',
          'PUNTOS GANADOS 12',
          'SALDO ANTERIOR 340.00',
          'SALDO ACTUAL 352.00',
        ]),
        12040,
      );
      expectPaid(
        read([
          'SORIANA',
          '23/11/2026 19:02',
          'ARROZ 1KG 32.90',
          'FRIJOL 1KG 41.50',
          'ACEITE 1L 46.00',
          'TOTAL 120.40',
          'EFECTIVO 150.00',
          'CAMBIO 29.60',
          'SALDO EN TARJETA DE PUNTOS: 185.00',
        ]),
        12040,
      );
    });

    test('a bill for a service: previous balance and payment received', () {
      expectPaid(
        read([
          'TELEFONOS EJEMPLO SA DE CV',
          'ESTADO DE CUENTA NOVIEMBRE 2026',
          'SALDO ANTERIOR 598.00',
          'SU PAGO GRACIAS 598.00',
          'CARGOS DEL MES 612.00',
          'TOTAL A PAGAR 612.00',
        ]),
        61200,
      );
    });
  });

  group('restaurants', () {
    const bill = [
      'RESTAURANTE LA CASONA',
      'MESA 14 PERSONAS 2',
      '23/11/2026 14:35',
      '2 ENCHILADAS SUIZAS 290.00',
      '1 SOPA AZTECA 95.00',
      '2 AGUA DE JAMAICA 90.00',
      r'SUBTOTAL $409.48',
      r'IVA 16% $65.52',
      r'TOTAL $475.00',
    ];

    test('a table of suggested tips was not paid', () {
      expectPaid(
        read([
          ...bill,
          'PROPINA SUGERIDA',
          r'10% $47.50   15% $71.25   20% $95.00',
          'ESTE NO ES UN COMPROBANTE FISCAL',
        ]),
        47500,
      );
      expectPaid(
        read([
          ...bill,
          'PROPINA SUGERIDA (NO OBLIGATORIA)',
          r'10% $47.50 TOTAL $522.50',
          r'15% $71.25 TOTAL $546.25',
          r'20% $95.00 TOTAL $570.00',
        ]),
        47500,
      );
      // The percentages on one row, the amounts on the next.
      expectPaid(
        read([
          ...bill,
          'PROPINA SUGERIDA',
          '10%   15%   20%',
          '47.50   71.25   95.00',
          'TOTAL CON PROPINA',
          '522.50   546.25   570.00',
        ]),
        47500,
      );
      expectPaid(
        read([
          'BLUE DINER',
          '11/20/2026 12:30 PM',
          'Pancakes 14.00',
          'Coffee 6.00',
          'Subtotal 20.00',
          'Tax 1.78',
          'Total 21.78',
          'Suggested Gratuity',
          r'18% $3.92   20% $4.36   22% $4.79',
        ], home: 'USD', monthFirst: true),
        2178,
      );
    });

    test('a tip that was added is part of what was paid', () {
      expectPaid(
        read([
          ...bill,
          r'PROPINA $71.25',
          r'TOTAL CON PROPINA $546.25',
        ]),
        54625,
      );
      // "Otro" is how some tills label the tip.
      expectPaid(
        read([
          'CAFE EJEMPLO',
          "23 Nov'26 09:02 AM",
          '1 LATTE GRANDE 85.00',
          '1 PANINI 65.00',
          r'Subtotal $150.00',
          r'Otro $15.00',
          r'Total Pagado $165.00',
          r'Tarjeta Debito $165.00',
        ]),
        16500,
      );
    });

    test('tip paid in cash: what was handed over less the change', () {
      expectPaid(
        read([
          'LA PARRILLA NORTENA',
          '23/11/2026 15:10',
          '2 ARRACHERA 300.00',
          '2 CERVEZA 128.50',
          'TOTAL 428.50',
          'PROPINA 42.85',
          'EFECTIVO 500.00',
          'CAMBIO 28.65',
        ]),
        47135,
      );
    });

    test('the tax-included note beside the total', () {
      expectPaid(
        read([
          'FONDA DONA MARY',
          '23/11/2026 14:02',
          '2 COMIDA CORRIDA 190.00',
          '2 AGUA FRESCA 50.00',
          r'TOTAL (IVA 16% INCLUIDO) $240.00',
        ]),
        24000,
      );
    });

    test('card slip from the terminal: sale, tip, total', () {
      expectPaid(
        read([
          'RESTAURANTE LA CASONA',
          'BBVA',
          'VENTA',
          'TARJETA: ************1234',
          'VISA CREDITO',
          r'IMPORTE: $475.00',
          r'PROPINA: $71.25',
          r'TOTAL: $546.25',
          'APROBADA',
          'AUT: 123456',
        ]),
        54625,
      );
      expectPaid(
        read([
          'CAFE EJEMPLO',
          'SANTANDER',
          'AFILIACION: 1000001',
          'TARJETA: ************1234',
          'VENTA',
          r'IMPORTE $250.00',
          r'PROPINA $0.00',
          r'TOTAL M.N. $250.00',
          'APROBADA 123456',
        ]),
        25000,
      );
    });

    test('US bill with the tip and total left blank to write in', () {
      expectPaid(
        read([
          'OLIVE TREE GRILL',
          '11/20/2026 7:42 PM',
          'Lasagna 18.99',
          'Chicken Alfredo 20.49',
          'Soda 3.29',
          'Subtotal 42.77',
          'Tax 3.53',
          'Total 46.30',
          'Tip: ________',
          'Total: ________',
          'X',
        ], home: 'USD', monthFirst: true),
        4630,
      );
      expectPaid(
        read([
          'OLIVE TREE GRILL',
          '11/20/2026 7:42 PM',
          'VISA ************1234',
          r'Amount $46.30',
          r'Tip $8.00',
          r'Total $54.30',
          'APPROVED 01234Z',
        ], home: 'USD', monthFirst: true),
        5430,
      );
    });

    test('UK bill with a service charge', () {
      expectPaid(
        read([
          'THE BOMBAY CANTEEN',
          'Table 12 Covers 2',
          '23/11/2026 19:45',
          '2 Chicken Ruby 29.80',
          '1 Black Daal 8.90',
          '2 Naan 7.80',
          'Subtotal 46.50',
          'Service Charge 12.5% 5.81',
          'Total £52.31',
        ], home: 'USD'),
        5231,
        currency: 'GBP',
      );
    });
  });

  group('fuel, tolls, parking, taxis', () {
    test('litres x price per litre = amount', () {
      expectPaid(
        read([
          'SERVICIO EJEMPLO SA DE CV',
          'ESTACION 01234',
          'RFC XXX010101AB1',
          '23/11/2026 07:12',
          'BOMBA 04 MAGNA',
          'LITROS 35.238',
          r'PRECIO $23.99',
          r'IMPORTE $845.36',
          r'TOTAL $845.36',
          r'EFECTIVO $900.00',
          r'CAMBIO $54.64',
        ]),
        84536,
      );
      expectPaid(
        read([
          'GASOLINERA EJEMPLO',
          '23/11/2026 07:12',
          'PRODUCTO LITROS PRECIO IMPORTE',
          'MAGNA 35.238 23.99 845.36',
          'SUBTOTAL 728.76',
          'IVA 116.60',
          'TOTAL 845.36',
          'TOTAL LITROS 35.238',
          'VISA ************1234',
        ]),
        84536,
      );
      // Only the litres and the amount are labelled.
      expectPaid(
        read([
          'GASOLINERA EJEMPLO',
          '23/11/2026 07:12',
          'DIESEL',
          'TOTAL LITROS: 35.238',
          r'PRECIO X LITRO: $23.99',
          r'IMPORTE: $845.36',
        ]),
        84536,
      );
    });

    test('toll booth', () {
      expectPaid(
        read([
          'CAMINOS Y PUENTES FEDERALES',
          'PLAZA DE COBRO 078 TEPOTZOTLAN',
          '23/11/2026 06:15:22',
          'CARRIL 05 CLASE AUTOMOVIL',
          r'IMPORTE $118.00',
          'IVA INCLUIDO',
          'FOLIO 0012345',
        ]),
        11800,
      );
    });

    test('car park: the hourly rate is not the charge', () {
      expectPaid(
        read([
          'ESTACIONAMIENTO CENTRAL',
          'BOLETO 004512',
          'ENTRADA 23/11/2026 08:15',
          'SALIDA 23/11/2026 10:50',
          'TIEMPO 02:35',
          r'TARIFA POR HORA $24.00',
          r'TOTAL A PAGAR $72.00',
          r'EFECTIVO $100.00',
          r'CAMBIO $28.00',
        ]),
        7200,
      );
    });

    test('taxi ticket that calls the fare a service', () {
      expectPaid(
        read([
          'SITIO 300 TAXI SEGURO',
          'BOLETO 123456',
          '23/11/2026 22:19',
          'DESTINO ZONA 4 POLANCO',
          r'IMPORTE DEL SERVICIO $440.00',
        ]),
        44000,
      );
    });

    test('ride apps by e-mail', () {
      expectPaid(
        read([
          'Uber',
          '23 nov 2026',
          'Gracias por viajar, Juan',
          r'Total MX$189.53',
          r'Tarifa del viaje MX$152.00',
          r'Subtotal MX$152.00',
          r'Cuota de solicitud MX$22.53',
          r'Propina MX$15.00',
          'Pagos',
          r'Visa ••••1234 MX$189.53',
        ], home: 'USD'),
        18953,
        currency: 'MXN',
      );
      expectPaid(
        read([
          'DiDi',
          'Recibo de viaje',
          '23/11/2026 08:12',
          r'Tarifa base $18.00',
          r'Distancia $42.30',
          r'Tiempo $15.20',
          r'Cuota de servicio $10.00',
          r'Total $85.50',
          r'Pagado con tarjeta •••• 1234 $85.50',
        ]),
        8550,
      );
    });
  });

  group('hotels', () {
    test('folio: charges, payment, balance 0.00', () {
      expectPaid(
        read([
          'HOTEL EJEMPLO REFORMA',
          'FOLIO 45678 HAB 512',
          'HUESPED JUAN PEREZ',
          'LLEGADA 21/11/2026 SALIDA 23/11/2026',
          '21/11 HABITACION 2,100.00',
          '21/11 IVA 16% 336.00',
          '21/11 ISH 3.5% 73.50',
          '22/11 HABITACION 2,100.00',
          '22/11 IVA 16% 336.00',
          '22/11 ISH 3.5% 73.50',
          '22/11 RESTAURANTE 485.00',
          'TOTAL CARGOS 5,504.00',
          'PAGO TARJETA VISA 5,504.00',
          'TOTAL ABONOS 5,504.00',
          'SALDO 0.00',
        ]),
        550400,
      );
      expectPaid(
        read([
          'MARRIOTT DOWNTOWN',
          'Guest Folio',
          'Arrival 11/18/2026 Departure 11/20/2026',
          '11/18 Room Charge 189.00',
          '11/18 State Tax 11.34',
          '11/18 City Tax 15.12',
          '11/19 Room Charge 189.00',
          '11/19 State Tax 11.34',
          '11/19 City Tax 15.12',
          '11/20 Visa XXXX1234 -430.92',
          'Total Charges 430.92',
          'Total Payments -430.92',
          'Balance Due 0.00',
        ], home: 'USD', monthFirst: true),
        43092,
      );
    });
  });

  group('Guatemala (quetzales)', () {
    test('restaurant factura, Q against the figures', () {
      expectPaid(
        read([
          'RESTAURANTE EL PORTAL',
          'NIT: 1234567-8',
          'FACTURA ELECTRONICA',
          'SERIE A1B2C3D4 No. 1234567890',
          'FECHA 23/11/2026 13:05',
          '2 DESAYUNO CHAPIN Q90.00',
          '1 CAFE Q15.00',
          '1 JUGO DE NARANJA Q20.00',
          'SUBTOTAL Q125.00',
          'PROPINA 10% Q12.50',
          'TOTAL Q137.50',
          'IVA 12% INCLUIDO',
          'SUJETO A PAGOS TRIMESTRALES ISR',
        ]),
        13750,
        currency: 'GTQ',
      );
    });

    test('Q. with a full stop, Q with a space', () {
      expectPaid(
        read([
          'CAFETERIA LA ANTIGUA',
          '23/11/2026 08:30',
          '2 DESAYUNO TIPICO Q.90.00',
          '1 CAFE Q.15.00',
          'TOTAL Q.105.00',
        ]),
        10500,
        currency: 'GTQ',
      );
      expectPaid(
        read([
          'SUPERMERCADO LA TORRE',
          'NIT 1234567-8',
          '23/11/2026 17:20',
          'FRIJOL NEGRO 1LB Q 12.50',
          'TORTILLAS Q 10.00',
          'POLLO ENTERO Q 64.25',
          'TOTAL Q 86.75',
          'EFECTIVO Q 100.00',
          'CAMBIO Q 13.25',
        ]),
        8675,
        currency: 'GTQ',
      );
    });

    test('ISO code on an app receipt', () {
      expectPaid(
        read([
          'Uber',
          '23 nov 2026',
          'Total GTQ 45.60',
          'Tarifa del viaje GTQ 38.00',
          'Cuota de solicitud GTQ 7.60',
        ]),
        4560,
        currency: 'GTQ',
      );
    });

    test('fuel in gallons', () {
      expectPaid(
        read([
          'ESTACION DE SERVICIO EJEMPLO',
          'NIT 1234567-8',
          '23/11/2026 06:48',
          'SUPER 8.512 GAL x Q 29.49',
          'TOTAL Q 251.02',
          'EFECTIVO Q 300.00',
          'CAMBIO Q 48.98',
        ]),
        25102,
        currency: 'GTQ',
      );
    });

    test('card slip with the tip', () {
      expectPaid(
        read([
          'RESTAURANTE EL PORTAL',
          'VENTA',
          'TARJETA ************1234',
          'MONTO Q 125.00',
          'PROPINA Q 12.50',
          'TOTAL Q 137.50',
          'AUTORIZACION 123456',
        ], home: 'GTQ'),
        13750,
        currency: 'GTQ',
      );
    });

    test('the amount in words names the currency and settles a misread', () {
      // No Q beside the figures: the words say quetzales.
      expectPaid(
        read([
          'HOTEL CASA EJEMPLO',
          'NIT 1234567-8',
          'FACTURA SERIE A No. 4521',
          '23/11/2026',
          '2 NOCHES HABITACION DOBLE 1,116.07',
          'IVA 12% 133.93',
          'TOTAL 1,250.00',
          'TOTAL EN LETRAS: UN MIL DOSCIENTOS CINCUENTA QUETZALES EXACTOS',
        ]),
        125000,
        currency: 'GTQ',
      );
      // A digit of the total misread; the words have it.
      expectPaid(
        read([
          'RESTAURANTE EL PORTAL',
          '23/11/2026 13:05',
          '2 DESAYUNO CHAPIN Q90.00',
          '1 CAFE Q15.00',
          '1 JUGO DE NARANJA Q32.50',
          'TOTAL Q187.50',
          'CIENTO TREINTA Y SIETE QUETZALES CON 50/100',
        ], home: 'GTQ'),
        13750,
        currency: 'GTQ',
      );
    });
  });

  group('US dollars in El Salvador, Panama, Ecuador', () {
    test('Salvadoran supermarket', () {
      expectPaid(
        read([
          'SUPER SELECTOS',
          'CALLEJA S.A. DE C.V.',
          'NIT 0614-123456-001-2 NRC 123-4',
          'FACTURA CONSUMIDOR FINAL',
          '23/11/2026 17:40',
          'LECHE ENTERA 1L 1.65 G',
          'PAN FRANCES 0.85 G',
          'CAFE MOLIDO 400G 4.95 G',
          'SUMAS 7.45',
          'VENTAS GRAVADAS 7.45',
          r'TOTAL $7.45',
          r'EFECTIVO $10.00',
          r'CAMBIO $2.55',
        ], home: 'USD'),
        745,
        currency: 'USD',
      );
    });

    test('pupuseria with 10% tip', () {
      expectPaid(
        read([
          'PUPUSERIA LA CEIBA',
          'SAN SALVADOR',
          '23/11/2026 12:48',
          '4 PUPUSA REVUELTA 4.00',
          '2 PUPUSA QUESO 2.00',
          '2 HORCHATA 3.00',
          r'SUB-TOTAL $9.00',
          r'PROPINA 10% $0.90',
          r'TOTAL A PAGAR $9.90',
        ], home: 'USD'),
        990,
      );
    });

    test('Panama: B/. against the figures', () {
      expectPaid(
        read([
          'CAFE CASCO VIEJO',
          'RUC 1234567-1-123456 DV 12',
          '23/11/2026 10:05',
          '2 CAFE GEISHA 12.00',
          '1 EMPAREDADO 6.50',
          'SUBTOTAL B/.18.50',
          'ITBMS 7% B/.1.30',
          'TOTAL B/.19.80',
        ], home: 'USD'),
        1980,
      );
    });

    test('Ecuador: two subtotals by tax rate', () {
      expectPaid(
        read([
          'RESTAURANTE EJEMPLO',
          'RUC 1790012345001',
          'FACTURA 001-001-000012345',
          '23/11/2026 13:20',
          '2 ALMUERZO EJECUTIVO 10.00',
          '1 AGUA SIN GAS 2.50',
          'SUBTOTAL 15% 10.00',
          'SUBTOTAL 0% 2.50',
          'IVA 15% 1.50',
          'VALOR TOTAL 14.00',
        ], home: 'USD'),
        1400,
      );
    });
  });

  group('Venezuela (bolivares)', () {
    const fiscal = [
      'SENIAT',
      'RIF J-00000001-1',
      'RESTAURANT EJEMPLO, C.A.',
      'FACTURA 00012345',
      'FECHA 23/11/2026 HORA 13:20',
      '2 PABELLON Bs 3.200,00',
      '2 JUGO NATURAL Bs 1.295,19',
      'SUBTTL Bs 4.495,19',
      'BI G (16,00%) Bs 4.495,19',
      'IVA G (16,00%) Bs 719,23',
      'IGTF 3,00% Bs 156,43',
      'TOTAL Bs 5.370,85',
    ];

    test('IGTF added; the dollar reference is not what was paid', () {
      expectPaid(
        read([...fiscal, 'TASA BCV 370,40', 'TOTAL REF USD 14,50'], home: 'VES'),
        537085,
        currency: 'VES',
      );
      // Scanned without a trip set: still bolivares.
      expectPaid(
        read([...fiscal, 'TASA BCV 370,40', 'TOTAL REF USD 14,50']),
        537085,
        currency: 'VES',
      );
      expectPaid(
        read([...fiscal, r'REF $ 14,50'], home: 'VES'),
        537085,
        currency: 'VES',
      );
    });

    test('Bs. hard against the figures, and Bs.D', () {
      expectPaid(
        read([
          'PANADERIA EJEMPLO, C.A.',
          'RIF J-00000001-1',
          '23/11/2026',
          '2 CACHITO Bs.740,00',
          '1 CAFE GRANDE Bs.555,60',
          'TOTAL Bs.1.295,60',
        ]),
        129560,
        currency: 'VES',
      );
      expectPaid(
        read([
          'PANADERIA EJEMPLO, C.A.',
          '23/11/2026',
          '2 CACHITO Bs.D 740,00',
          '1 CAFE GRANDE Bs.D 555,60',
          'TOTAL Bs.D 1.295,60',
        ]),
        129560,
        currency: 'VES',
      );
    });
  });

  group('other currencies', () {
    test('Colombian pesos: a dot for thousands, no decimals', () {
      expectPaid(
        read([
          'RESTAURANTE EJEMPLO SAS',
          'NIT 900.123.456-7',
          'FACTURA ELECTRONICA DE VENTA FE 12345',
          '23/11/2026 13:15',
          r'2 BANDEJA PAISA $ 76.000',
          r'2 LIMONADA DE COCO $ 24.000',
          r'SUBTOTAL $ 100.000',
          r'IMPOCONSUMO 8% $ 8.000',
          r'PROPINA VOLUNTARIA 10% $ 10.000',
          r'TOTAL $ 118.000',
        ], home: 'COP'),
        11800000,
      );
      expectPaid(
        read([
          'TIENDA EJEMPLO',
          '23/11/2026',
          r'1 CAFE EXCELSO 500G $ 45.000',
          r'TOTAL $ 45.000',
          r'EFECTIVO $ 50.000',
          r'CAMBIO $ 5.000',
        ], home: 'COP'),
        4500000,
      );
    });

    test('Chilean pesos have no decimals at all', () {
      expectPaid(
        read([
          'CAFE EJEMPLO SPA',
          'RUT 76.123.456-7',
          'BOLETA ELECTRONICA 123456',
          '23/11/2026 09:10',
          '2 CAFE LATTE 5.800',
          '1 MEDIALUNA 2.100',
          r'NETO $ 6.639',
          r'IVA 19% $ 1.261',
          r'TOTAL $ 7.900',
        ], home: 'CLP'),
        7900,
      );
    });

    test('Costa Rican colones', () {
      expectPaid(
        read([
          'SODA TIPICA EJEMPLO',
          'CEDULA JURIDICA 3-101-123456',
          'FACTURA ELECTRONICA',
          '23/11/2026 12:30',
          '2 CASADO CON POLLO ₡9,000.00',
          '2 FRESCO NATURAL ₡3,000.00',
          'SUBTOTAL ₡12,000.00',
          'SERVICIO 10% ₡1,200.00',
          'IVA 13% ₡1,560.00',
          'TOTAL ₡14,760.00',
        ]),
        1476000,
        currency: 'CRC',
      );
    });

    test('Honduran lempiras', () {
      expectPaid(
        read([
          'RESTAURANTE EJEMPLO',
          'RTN 08011999123456',
          'FACTURA 000-001-01-00012345',
          '23/11/2026 13:02',
          '2 BALEADA ESPECIAL L 120.00',
          '1 PLATO TIPICO L 185.00',
          '2 REFRESCO L 60.00',
          'SUBTOTAL L 365.00',
          'ISV 15% L 54.75',
          'TOTAL A PAGAR L 419.75',
        ]),
        41975,
        currency: 'HNL',
      );
      expectPaid(
        read([
          'HOTEL EJEMPLO',
          'RTN 08011999123456',
          '23/11/2026',
          '1 NOCHE HABITACION SENCILLA L. 1,850.00',
          'ISV 15% L. 277.50',
          'IMPUESTO TURISMO 4% L. 74.00',
          'TOTAL L. 2,201.50',
          'DOS MIL DOSCIENTOS UN LEMPIRAS CON 50/100',
        ]),
        220150,
        currency: 'HNL',
      );
    });

    test('Brazilian reais: comma for decimals, dot for thousands', () {
      expectPaid(
        read([
          'PADARIA EXEMPLO LTDA',
          'CNPJ 12.345.678/0001-90',
          'CUPOM FISCAL ELETRONICO - SAT',
          '23/11/2026 08:20',
          '001 PAO DE QUEIJO 3 UN X 6,50 19,50',
          '002 CAFE EXPRESSO 2 UN X 8,00 16,00',
          r'TOTAL R$ 35,50',
          'Cartao de Debito 35,50',
        ]),
        3550,
        currency: 'BRL',
      );
      expectPaid(
        read([
          'HOTEL EXEMPLO',
          '23/11/2026',
          r'2 DIARIAS R$ 1.100,00',
          r'TAXA DE SERVICO 10% R$ 110,00',
          r'ISS 5% R$ 24,56',
          r'VALOR TOTAL R$ 1.234,56',
        ]),
        123456,
        currency: 'BRL',
      );
    });

    test('pounds and euros', () {
      expectPaid(
        read([
          'PRET A MANGER',
          'VAT No. GB 123 4567 89',
          '23/11/2026 12:41',
          'Chicken Caesar Baguette 5.75',
          'Flat White 3.60',
          'TOTAL £9.35',
          'VAT @ 20.00% 1.56',
          'Card £9.35',
        ]),
        935,
        currency: 'GBP',
      );
      expectPaid(
        read([
          'BAR EJEMPLO',
          'NIF B12345678',
          '23/11/2026 14:10',
          '2 MENU DEL DIA 21,00',
          '1 CAFE SOLO 2,40',
          'BASE IMPONIBLE 21,27',
          'IVA 10% 2,13',
          'TOTAL 23,40 €',
          'ENTREGADO 50,00 €',
          'CAMBIO 26,60 €',
        ]),
        2340,
        currency: 'EUR',
      );
    });

    test('a second total in another currency', () {
      // Priced in pesos, with the dollar equivalent underneath.
      expectPaid(
        read([
          'TIENDA LIBRE DE IMPUESTOS',
          'AEROPUERTO INTERNACIONAL T1',
          '23/11/2026 06:20',
          '1 CHOCOLATE 380.00',
          '1 PERFUME 1,150.00',
          'TOTAL MXN 1,530.00',
          'TOTAL USD 84.07',
          'T.C. 18.20',
        ]),
        153000,
        currency: 'MXN',
      );
      // Priced in dollars with the peso equivalent: either is right, as long
      // as the amount and the currency belong together.
      final p = read([
        'TIENDA LIBRE DE IMPUESTOS',
        'AEROPUERTO INTERNACIONAL T1',
        '23/11/2026 06:20',
        '1 CHOCOLATE USD 4.50',
        '1 WHISKY 1L USD 17.00',
        'TOTAL USD 21.50',
        'TOTAL MXN 391.30',
        'TIPO DE CAMBIO 18.20',
      ]);
      expect(
        (p.amountMinor, p.currency),
        anyOf((2150, 'USD'), (39130, 'MXN')),
      );
    });
  });

  group('damage from the camera', () {
    const items = [
      'CAFETERIA EJEMPLO',
      '23/11/2026 09:15',
      '2 CHILAQUILES 290.00',
      '1 JUGO VERDE 95.00',
      '2 CAFE AMERICANO 90.00',
    ];

    test(r'the $ read as S, 5 or 8', () {
      expectPaid(read([...items, 'TOTAL S475.00']), 47500);
      expectPaid(read([...items, 'TOTAL 5475.00']), 47500);
      expectPaid(
        read([
          ...items,
          r'SUBTOTAL $409.48',
          r'IVA $65.52',
          'TOTAL 8475.00',
        ]),
        47500,
      );
    });

    test('the decimal point lost, or read as a comma or a space', () {
      expectPaid(read([...items, 'TOTAL 475,00']), 47500);
      expectPaid(read([...items, r'TOTAL $475 00']), 47500);
      expectPaid(read([...items, 'TOTAL 47500']), 47500);
    });

    test('a space inside the number', () {
      expectPaid(
        read([
          'MUEBLERIA EJEMPLO',
          '23/11/2026',
          r'1 SILLA EJECUTIVA $1,250.00',
          r'TOTAL $ 1, 250.00',
        ]),
        125000,
      );
      expectPaid(
        read([
          'MUEBLERIA EJEMPLO',
          '23/11/2026',
          r'1 SILLA EJECUTIVA $1,250.00',
          r'TOTAL $1 ,250 .00',
        ]),
        125000,
      );
    });

    test('dots leading from the label to the amount', () {
      expectPaid(read([...items, 'TOTAL..........475.00']), 47500);
      expectPaid(
        read([
          ...items,
          'SUBTOTAL.......409.48',
          'IVA.............65.52',
          'TOTAL..........475.00',
        ]),
        47500,
      );
    });

    test('each label on one row and its amount on the next', () {
      expectPaid(
        read([
          ...items,
          'SUBTOTAL',
          r'$409.48',
          'IVA 16%',
          r'$65.52',
          'TOTAL',
          r'$475.00',
        ]),
        47500,
      );
    });

    test('the labels read as one block and the amounts as another', () {
      expectPaid(
        read([
          'RESTAURANTE EJEMPLO',
          '23/11/2026 15:00',
          '2 TACOS DE ARRACHERA',
          '1 AGUA MINERAL',
          'SUBTOTAL',
          'IVA',
          'TOTAL',
          '400.00',
          '445.36',
          '728.76',
          '116.60',
          '845.36',
        ]),
        84536,
      );
      expectPaid(
        read([
          'RESTAURANTE EJEMPLO',
          '23/11/2026 15:00',
          '2 TACOS DE ARRACHERA 400.00',
          '1 AGUA MINERAL 445.36',
          'SUBTOTAL',
          'IVA',
          'TOTAL',
          '728.76',
          '116.60',
          '845.36',
        ]),
        84536,
      );
    });

    test('the total printed twice', () {
      expectPaid(
        read([
          ...items,
          r'TOTAL $475.00',
          'PAGO CON TARJETA',
          'VISA ************1234',
          r'TOTAL $475.00',
          'APROBADA',
        ]),
        47500,
      );
    });

    test('the currency code after the amount', () {
      expectPaid(
        read([...items, r'TOTAL $475.00 MXN'], home: 'USD'),
        47500,
        currency: 'MXN',
      );
    });

    test('total row lost: the count of items is never the amount', () {
      final p = read([...items, 'TOTAL ARTICULOS 5', 'GRACIAS POR SU VISITA']);
      expect(p.amountMinor, 47500);
      expect(p.amountDoubtful, isTrue);
    });
  });

  group('amount in words', () {
    WordsAmount? words(String row) {
      final found = AmountInWords.find([row]);
      return found.isEmpty ? null : found.first;
    }

    test('quetzales, lempiras, dollars, bolivares', () {
      for (final (row, whole, cents) in [
        ('CIENTO TREINTA Y SIETE QUETZALES CON 50/100', 137, 50),
        ('TOTAL EN LETRAS: UN MIL DOSCIENTOS CINCUENTA QUETZALES EXACTOS', 1250, null),
        ('Q. CIENTO VEINTICINCO CON 50/100', 125, 50),
        ('DOS MIL DOSCIENTOS UN LEMPIRAS CON 50/100', 2201, 50),
        ('SON: TREINTA Y UN 42/100 DOLARES', 31, 42),
        ('VALOR EN LETRAS: NUEVE DOLARES CON 90/100', 9, 90),
        ('SON: CINCO MIL TRESCIENTOS SETENTA BOLIVARES CON 85/100', 5370, 85),
        ('CUARENTA Y CINCO MIL PESOS M/CTE', 45000, null),
      ]) {
        final amount = words(row);
        expect(amount, isNotNull, reason: row);
        expect(amount!.whole, whole, reason: row);
        expect(amount.cents, cents, reason: row);
        expect(amount.formal, isTrue, reason: row);
      }
    });

    test('words and figures disagree and nothing settles it: flagged', () {
      final p = read([
        'FERRETERIA EJEMPLO',
        '23/11/2026',
        r'TOTAL $1,860.00',
        '(UN MIL OCHOCIENTOS PESOS 00/100 M.N.)',
      ]);
      expect(p.amountDoubtful, isTrue);
      expect(p.amountMinor, anyOf(186000, 180000));
    });
  });
}

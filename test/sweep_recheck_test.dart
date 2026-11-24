import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receipts an independent check used to break rules of the item reader.
/// Every case here was a wrong result once.

/// Items as "quantity|description|amount" (blank where not printed).
List<String> read(List<String> rows) => [
      for (final i in ItemLineParser.extract(rows))
        '${i.quantity ?? ''}|${i.description}|${i.amountText ?? ''}',
    ];

/// Items as "description|amount".
List<String> priced(List<String> rows) => [
      for (final i in ItemLineParser.extract(rows))
        '${i.description}|${i.amountText ?? ''}',
    ];

void main() {
  group('a letter after a figure: tax mark or size', () {
    test('sizes on the name row, the price on the row below', () {
      expect(
        read([
          'AGUA PURA 1.50 L',
          '2 x 8.00 16.00',
          'GASEOSA COLA 2.50 L',
          '1 x 18.00 18.00',
          'JUGO NARANJA 1.00 L',
          '1 x 12.50 12.50',
        ]),
        [
          '2|AGUA PURA 1.50 L|16.00',
          '1|GASEOSA COLA 2.50 L|18.00',
          '1|JUGO NARANJA 1.00 L|12.50',
        ],
      );
      expect(
        priced([
          'ARROZ 1.00 K',
          '1 x 28.00 28.00',
          'FRIJOL 2.00 K',
          '1 x 60.00 60.00',
          'AZUCAR 1.00 K',
          '2 x 25.00 50.00',
        ]),
        ['ARROZ 1.00 K|28.00', 'FRIJOL 2.00 K|60.00', 'AZUCAR 1.00 K|50.00'],
      );
    });

    test('size notes under priced items get no price', () {
      expect(
        priced([
          '1 REFRESCO COLA 38.00',
          'RETORNABLE 2.50 L',
          '1 AGUA MINERAL 22.00',
          'BOTELLA 1.50 L',
          '1 CERVEZA CAGUAMA 48.00',
          'ENVASE 1.20 L',
        ]),
        [
          'REFRESCO COLA|38.00',
          'RETORNABLE 2.50 L|',
          'AGUA MINERAL|22.00',
          'BOTELLA 1.50 L|',
          'CERVEZA CAGUAMA|48.00',
          'ENVASE 1.20 L|',
        ],
      );
    });

    test('names with sizes, then the prices as a block: nothing is guessed '
        'from the sizes', () {
      final items = priced([
        'AGUA PURA 1.50 L',
        'GASEOSA COLA 2.50 L',
        'JUGO NARANJA 1.00 L',
        '14.00',
        '38.00',
        '26.50',
      ]);
      expect(items, isNot(contains('AGUA PURA|1.50')));
      expect(items, isNot(contains('GASEOSA COLA|2.50')));
    });

    test('a short Salvadoran ticket: G after the price is the tax mark', () {
      expect(
        read(['2 PUPUSA REVUELTA 2.30 G', '1 HORCHATA 1.25 G', 'TOTAL 3.55']),
        ['2|PUPUSA REVUELTA|2.30', '1|HORCHATA|1.25'],
      );
    });

    test('the size before the price on the same row stays in the name', () {
      expect(
        priced([
          '1 AGUA CIEL 1.50 L 14.00',
          '1 AGUA CIEL 1.50 L 14.00',
          '1 AGUA CIEL 1.50 L 14.00',
          'TOTAL 42.00',
        ]),
        List.filled(3, 'AGUA CIEL 1.50 L|14.00'),
      );
    });
  });

  group('savings and counts between the items and the total', () {
    test('a saving row of the totals block is not an item', () {
      for (final saving in [
        'AHORRO EN ESTA COMPRA -5.00',
        'DESCUENTOS EMPLEADO -12.40',
        r'DESCUENTOS PROMOCION $-5.00',
        'AHORRO CLIENTE FRECUENTE 5.00-',
        'AHORRO MONEDERO -6.00',
        'SAVINGS CLUBCARD -0.50',
        'SAVINGS TODAY -1.20',
      ]) {
        expect(
          priced(['1 LECHE LALA 1L 26.50', saving, 'TOTAL 21.50']),
          ['LECHE LALA 1L|26.50'],
          reason: saving,
        );
      }
    });

    test('a saving named after the product above it is a line', () {
      expect(
        priced([
          'CAFE NESCAFE 225G 132.00',
          'AHORRO CAFE NESCAFE -12.00',
          'PAPEL HIG REGIO 12R 89.90',
          'TOTAL 209.90',
        ]),
        [
          'CAFE NESCAFE 225G|132.00',
          'AHORRO CAFE NESCAFE|-12.00',
          'PAPEL HIG REGIO 12R|89.90',
        ],
      );
    });

    test('the number of pieces under a dish is a note, not the end', () {
      expect(
        priced([
          '1 CUBETA FAMILIAR 329.00',
          '12 PIEZAS',
          '1 REFRESCO 2L 45.00',
          'TOTAL 374.00',
        ]),
        ['CUBETA FAMILIAR|329.00', '12 PIEZAS|', 'REFRESCO 2L|45.00'],
      );
      expect(
        [
          for (final i in ItemLineParser.extract([
            '1 ALITAS BBQ 189.00',
            '12 PZAS',
            '1 BONELESS MANGO HABANERO 169.00',
            '10 PZAS',
            '1 CERVEZA CLARA 55.00',
          ]))
            if (i.amountText != null) i.description,
        ],
        ['ALITAS BBQ', 'BONELESS MANGO HABANERO', 'CERVEZA CLARA'],
      );
    });

    test('a count of things bought still is not an item', () {
      expect(
        priced(['1 ADVIL 8.49', '1 AGUA 2.29', '2 ITEMS', 'TOTAL 10.78']),
        ['ADVIL|8.49', 'AGUA|2.29'],
      );
      expect(
        priced(['6 PIEZAS POLLO 129.00', '2 ITEMS COMBO 99.00', 'TOTAL 228']),
        ['POLLO|129.00', 'ITEMS COMBO|99.00'],
      );
    });

    test('products named after a totals word', () {
      expect(
        priced([
          'CREDIT CARD HOLDER 12.00',
          'LEATHER KEYRING 4.50',
          'BALANCE DUE 16.50',
        ]),
        ['CREDIT CARD HOLDER|12.00', 'LEATHER KEYRING|4.50'],
      );
      expect(
        priced([
          'EJEMPLO AUTO CLUB',
          'IDP APPLICATION FEE 20.00',
          'PASSPORT PHOTOS 15.00',
          'SUBTOTAL 35.00',
          'TOTAL 35.00',
        ]),
        ['IDP APPLICATION FEE|20.00', 'PASSPORT PHOTOS|15.00'],
      );
    });
  });

  group('one product printed as fields', () {
    test('the total is taken, not the unit price or the volume', () {
      expect(
        read([
          'PRODUCTO: CORRIENTE',
          'CANTIDAD: 8.524 GAL',
          r'VALOR UNITARIO: $15.800',
          r'VALOR TOTAL: $134.680',
        ]),
        ['8.524 GAL|CORRIENTE|134.680'],
      );
      expect(
        read([
          'PRODUCTO: MAGNA',
          'CANTIDAD: 38.462 LTS',
          r'VALOR UNITARIO: $23.89',
          r'IMPORTE: $918.86',
        ]),
        ['38.462 LTS|MAGNA|918.86'],
      );
      expect(
        read([
          'DESCRIPCION: CARTUCHO TINTA NEGRA',
          'CANTIDAD: 2',
          r'VALOR UNITARIO: $349.00',
          r'IMPORTE: $698.00',
        ]),
        ['2|CARTUCHO TINTA NEGRA|698.00'],
      );
      expect(
        priced([
          'PRODUCTO: SUPER',
          'PRECIO: Q 31.49',
          'TOTAL GALONES: 8.52',
          'TOTAL: Q 268.42',
        ]),
        ['SUPER|268.42'],
      );
    });

    test('the kind of transaction on a card voucher is not a product', () {
      expect(
        read([
          'TARJETA: ************1234',
          'CONCEPTO: VENTA',
          r'IMPORTE: $450.00',
        ]),
        isEmpty,
      );
      expect(
        read([
          'COMPROBANTE DE PAGO',
          'TARJETA: VISA ****1234',
          'DESCRIPCION: VENTA PRESENCIAL',
          'AUTORIZACION: 123456',
          r'TOTAL: $450.00',
        ]),
        isEmpty,
      );
    });
  });

  group('hotel folios', () {
    test('the lodging tax under any label is not an item', () {
      for (final tax in [
        '16/11/26 IMP. HOSPEDAJE 3% 64.50',
        '16/11/26 I.S.H. 3% 64.50',
        '16/11/26 3% HOSPEDAJE 64.50',
        '16/11/26 ISH 3% 64.50',
      ]) {
        expect(
          priced([
            '16/11/26 HABITACION 2,150.00',
            '16/11/26 IVA 16% 344.00',
            tax,
            'TOTAL 2,558.50',
          ]),
          ['HABITACION|2,150.00'],
          reason: tax,
        );
        expect(
          priced([
            '16/11/26 HABITACION 2,150.00',
            '16/11/26 IVA 16% 344.00',
            tax,
            '17/11/26 HABITACION 2,150.00',
            '17/11/26 IVA 16% 344.00',
            tax.replaceFirst('16/', '17/'),
            '17/11/26 RESTAURANTE 485.00',
            'TOTAL 5,602.00',
          ]),
          ['HABITACION|2,150.00', 'HABITACION|2,150.00', 'RESTAURANTE|485.00'],
          reason: 'two nights, $tax',
        );
      }
      expect(
        priced([
          '11/16/26 ROOM CHARGE 189.00',
          '11/16/26 STATE TAX 11.34',
          '11/16/26 OCCUPANCY TAX 9.45',
          '11/17/26 ROOM CHARGE 189.00',
          '11/17/26 STATE TAX 11.34',
          '11/17/26 OCCUPANCY TAX 9.45',
          'BALANCE DUE 419.58',
        ]),
        ['ROOM CHARGE|189.00', 'ROOM CHARGE|189.00'],
      );
    });

    test('a payment by transfer, agency or deposit is not an item', () {
      for (final payment in [
        '18/11/26 TRANSFERENCIA BANCARIA -4,988.00',
        '18/11/26 PREPAGO AGENCIA -4,988.00',
        '18/11/26 CXC AGENCIA EJEMPLO -4,988.00',
        '18/11/26 PAGO TARJETA VISA -4,988.00',
        '18/11/26 VISA XXXX1111 4,988.00',
      ]) {
        expect(
          priced([
            '16/11/26 HABITACION 2,150.00',
            '16/11/26 IVA 16% 344.00',
            '17/11/26 HABITACION 2,150.00',
            '17/11/26 IVA 16% 344.00',
            payment,
            'SALDO 0.00',
          ]),
          ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
          reason: payment,
        );
      }
    });

    test('a breakdown printed under the payment adds nothing', () {
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          '16/11/26 IVA 16% 344.00',
          '16/11/26 ISH 3% 64.50',
          '17/11/26 HABITACION 2,150.00',
          '17/11/26 IVA 16% 344.00',
          '17/11/26 ISH 3% 64.50',
          '18/11/26 PAGO TARJETA VISA -5,117.00',
          'DESGLOSE',
          'HOSPEDAJE 4,300.00',
          'IVA 688.00',
          'ISH 129.00',
          'TOTAL 5,117.00',
        ]),
        ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
      );
    });

    test('dates with the month as a word; tax rows with no date', () {
      expect(
        priced([
          '16-NOV-26 HABITACION 2,150.00',
          '16-NOV-26 IVA 16% 344.00',
          '17-NOV-26 HABITACION 2,150.00',
          '17-NOV-26 IVA 16% 344.00',
          'TOTAL 4,988.00',
        ]),
        ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
      );
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          'IVA 16% 344.00',
          'ISH 3% 64.50',
          '17/11/26 HABITACION 2,150.00',
          'IVA 16% 344.00',
          'ISH 3% 64.50',
          'TOTAL 5,117.00',
        ]),
        ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
      );
    });

    test('a refund on a folio takes its charge with it', () {
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          '16/11/26 MINIBAR 85.00',
          '17/11/26 HABITACION 2,150.00',
          '17/11/26 DEVOLUCION MINIBAR -85.00',
          'TOTAL 4,300.00',
        ]),
        ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
      );
    });

    test('dated instalments under one purchase are not a folio', () {
      expect(
        priced([
          '1 REFRIGERADOR 14 PIES 12,000.00',
          '01/09/2026 ABONO 2,000.00',
          '01/10/2026 ABONO 2,000.00',
          '01/11/2026 ABONO 2,000.00',
          'RESTA 6,000.00',
        ]),
        ['REFRIGERADOR 14 PIES|12,000.00'],
      );
    });
  });

  group('how many: "x2" after the name', () {
    test('a line number in front does not replace it', () {
      expect(
        read([
          '1 TACO PASTOR x2 44.00',
          '2 AGUA HORCHATA x1 35.00',
          'TOTAL 79.00',
        ]),
        ['2|TACO PASTOR|44.00', '1|AGUA HORCHATA|35.00'],
      );
      expect(
        read(['1 CERVEZA 45.00 x2 90.00', 'TOTAL 90.00']),
        ['2|CERVEZA|90.00'],
      );
    });

    test('a dish named with a number keeps its number', () {
      expect(
        read([
          'TACO PASTOR x5 110.00',
          'TACO SUADERO x3 66.00',
          '3 LECHES x2 170.00',
          '12 ALITAS BBQ x2 318.00',
          '7UP 600ML x2 70.00',
          'TOTAL 734.00',
        ]),
        [
          '5|TACO PASTOR|110.00',
          '3|TACO SUADERO|66.00',
          '2|3 LECHES|170.00',
          '2|12 ALITAS BBQ|318.00',
          '2|7UP 600ML|70.00',
        ],
      );
      expect(
        read(['2 TACOS Y REFRESCO x1 99.00', 'TOTAL 99.00']),
        ['1|2 TACOS Y REFRESCO|99.00'],
      );
    });

    test('without a number in front, and a pack size after a barcode', () {
      expect(
        read(['TACO AL PASTOR x2 44.00', 'COCA COLA 600ML X3 54.00']),
        ['2|TACO AL PASTOR|44.00', '3|COCA COLA 600ML|54.00'],
      );
      expect(
        priced(['4 7707654300019 JABON PROTEX X3 9.800', 'TOTAL 9.800']),
        ['JABON PROTEX X3|9.800'],
      );
    });
  });

  group('prices that OCR damaged', () {
    test('the last zero read as O with the tax letter stuck on', () {
      expect(
        read([
          '1 ADVIL TABS 200MG 24CT 8.49T',
          '1 HAND SANITIZER 2OZ 2.5OT',
          'TOTAL 10.99',
        ]),
        ['1|ADVIL TABS 200MG 24CT|8.49', '1|HAND SANITIZER 2OZ|2.50'],
      );
      expect(
        priced([
          'CAFE LATTE 59.0OE',
          'JUGO NARANJA 12.5OA',
          r'MUFFIN $7.5OT',
          'TOTAL 79.00',
        ]),
        ['CAFE LATTE|59.00', 'JUGO NARANJA|12.50', 'MUFFIN|7.50'],
      );
    });

    test('the same on the price row under the name', () {
      expect(
        read(['PARIS WARM BOWL', '1.00 x 12.30= 12.3OE', 'SUBTOTAL 12.30']),
        ['1|PARIS WARM BOWL|12.30'],
      );
      expect(
        read(['2 POLAND SPRING WTR 1L', '2 @ 2.25 4.5OB', 'TOTAL 4.50']),
        ['2|POLAND SPRING WTR 1L|4.50'],
      );
    });

    test('a measure in ounces is still part of the name', () {
      expect(
        priced(['2 MEZCAL ESPADIN 1.5OZ 280.00', 'TOTAL 280.00']),
        ['MEZCAL ESPADIN 1.5OZ|280.00'],
      );
    });
  });

  group('numbers in front of the name', () {
    test('an order that happens to count up keeps its quantities', () {
      expect(
        read([
          '1 GUACAMOLE 120.00',
          '2 SOPA AZTECA 170.00',
          '3 TACOS ARRACHERA 285.00',
          '4 AGUA DE JAMAICA 140.00',
        ]),
        [
          '1|GUACAMOLE|120.00',
          '2|SOPA AZTECA|170.00',
          '3|TACOS ARRACHERA|285.00',
          '4|AGUA DE JAMAICA|140.00',
        ],
      );
      expect(
        read([
          '1 GUACAMOLE 120.00 120.00',
          '2 SOPA AZTECA 85.00 170.00',
          '3 TACOS ARRACHERA 95.00 285.00',
          '4 AGUA DE JAMAICA 35.00 140.00',
          '5 CERVEZA 45.00 225.00',
        ]).map((line) => line.split('|').first),
        ['1', '2', '3', '4', '5'],
      );
    });

    test('quantities printed with zeros in front', () {
      expect(
        read([
          '002 TACO PASTOR 22.00 44.00',
          '001 AGUA MINERAL 30.00 30.00',
          'TOTAL 74.00',
        ]),
        ['2|TACO PASTOR|44.00', '1|AGUA MINERAL|30.00'],
      );
      expect(
        read(['010 TORTILLAS MAIZ 25.00', 'TOTAL 25.00']),
        ['10|TORTILLAS MAIZ|25.00'],
      );
    });

    test('line counters with zeros, and their product codes', () {
      expect(
        read([
          '001 1001 PRATO EXECUTIVO FRANGO',
          '1 UN x 38,90 38,90',
          '002 1045 SUCO DE LARANJA 300ML',
          '2 UN x 9,50 19,00',
          '003 1102 CAFE EXPRESSO',
          '1 UN x 6,00 6,00',
        ]),
        [
          '1|PRATO EXECUTIVO FRANGO|38,90',
          '2|SUCO DE LARANJA 300ML|19,00',
          '1|CAFE EXPRESSO|6,00',
        ],
      );
      expect(
        priced(['002 1800 REPOSADO 165.00', 'TOTAL 165.00']),
        ['1800 REPOSADO|165.00'],
      );
    });

    test('line numbers before barcodes: with a void, or three lines', () {
      expect(
        read([
          '1 7702001012345 AGUA CRISTAL 600ML 2.300',
          '2 7702004098765 PAN TAJADO BIMBO 7.950',
          '3 7702004098765 PAN TAJADO BIMBO -7.950',
          '4 7701234500012 CAFE SELLO ROJO 500G 21.900',
          '5 7707654300019 JABON PROTEX X3 9.800',
          '6 7702129012345 CHOCOLATINA JET 12U 13.500',
          'TOTAL A PAGAR 47.500',
        ]),
        [
          '|AGUA CRISTAL 600ML|2.300',
          '|CAFE SELLO ROJO 500G|21.900',
          '|JABON PROTEX X3|9.800',
          '|CHOCOLATINA JET 12U|13.500',
        ],
      );
      expect(
        read([
          '1 7702001012345 AGUA CRISTAL 600ML 2.300',
          '2 7702004098765 PAN TAJADO BIMBO 7.950',
          '3 7701234500012 CAFE SELLO ROJO 500G 21.900',
          'TOTAL A PAGAR 32.150',
        ]).map((line) => line.split('|').first),
        ['', '', ''],
      );
    });

    test('a table numbered by line with the quantity after the name', () {
      expect(
        read([
          '1 TACO PASTOR 2 22.00 44.00',
          '2 AGUA HORCHATA 1 35.00 35.00',
          '3 CERVEZA 3 45.00 135.00',
          '4 FLAN NAPOLITANO 1 45.00 45.00',
        ]),
        [
          '2|TACO PASTOR|44.00',
          '1|AGUA HORCHATA|35.00',
          '3|CERVEZA|135.00',
          '1|FLAN NAPOLITANO|45.00',
        ],
      );
    });

    test('a quantity before a name that begins with a figure', () {
      expect(
        read([
          '2 7UP 600ML 40.00',
          '1 3 LECHES 85.00',
          '1 1/2 POLLO ROSTIZADO 120.00',
          '2 20 ALITAS 398.00',
          '1 4 QUESOS PIZZA 189.00',
          '1 CAFE AMERICANO 35.00',
          'TOTAL 867.00',
        ]),
        [
          '2|7UP 600ML|40.00',
          '1|3 LECHES|85.00',
          '1|1/2 POLLO ROSTIZADO|120.00',
          '2|20 ALITAS|398.00',
          '1|4 QUESOS PIZZA|189.00',
          '1|CAFE AMERICANO|35.00',
        ],
      );
      expect(
        read(['101 355ML CORONA 35.00', 'TOTAL 35.00']).single,
        isNot(startsWith('101|')),
      );
    });
  });

  group('quantity, unit price and total on one row', () {
    test('with the unit printed beside the quantity', () {
      expect(
        read(['SUPER 8.524 GAL 31.49 268.42', 'TOTAL Q 268.42']),
        ['8.524 GAL|SUPER|268.42'],
      );
      expect(
        read(['MAGNA 35.214 LTS 23.99 844.78', 'TOTAL 844.78']),
        ['35.214 LTS|MAGNA|844.78'],
      );
      expect(
        read(['JAMON DE PAVO 0.250 KG 180.00 45.00', 'TOTAL 45.00']),
        ['0.250 KG|JAMON DE PAVO|45.00'],
      );
    });

    test('with a discount column, or a unit price of three decimals', () {
      expect(
        read(['SUPER 8.524 31.49 0.00 268.42', 'TOTAL 268.42']),
        ['8.524|SUPER|268.42'],
      );
      expect(
        read(['TACO AL PASTOR 2 22.00 0.00 44.00', 'TOTAL 44.00']),
        ['2|TACO AL PASTOR|44.00'],
      );
      expect(
        read(['UNLEADED 8.524 3.459 29.48', 'TOTAL 29.48']),
        ['8.524|UNLEADED|29.48'],
      );
    });
  });

  // ------------------------------------------------------------------
  // Second round: receipts that broke the first rework.
  group('round two: tax mark or size', () {
    test('sizes on name rows when every price carries a tax letter', () {
      expect(
        read([
          "TITO'S VODKA 1.75 L",
          '1 @ 34.99 34.99 T',
          'JACK DANIELS 1.00 L',
          '1 @ 32.99 32.99 T',
          'BACARDI SUPERIOR 1.75 L',
          '1 @ 24.99 24.99 T',
        ]),
        [
          "1|TITO'S VODKA 1.75 L|34.99",
          '1|JACK DANIELS 1.00 L|32.99',
          '1|BACARDI SUPERIOR 1.75 L|24.99',
        ],
      );
      expect(
        read(['AZAFRAN ESPANOL 1.00 G', '1 X 95.00 95.00 A']),
        ['1|AZAFRAN ESPANOL 1.00 G|95.00'],
      );
    });

    test('size notes under items whose prices carry a tax letter', () {
      expect(
        priced([
          '1 REFRESCO COLA 38.00 A',
          'RETORNABLE 2.50 L',
          '1 AGUA MINERAL 22.00 A',
          'BOTELLA 1.50 L',
          '1 CERVEZA CAGUAMA 48.00 A',
          'ENVASE 1.20 L',
          'TOTAL 108.00',
        ]),
        [
          'REFRESCO COLA|38.00',
          'RETORNABLE 2.50 L|',
          'AGUA MINERAL|22.00',
          'BOTELLA 1.50 L|',
          'CERVEZA CAGUAMA|48.00',
          'ENVASE 1.20 L|',
        ],
      );
    });

    test('El Salvador: G is the tax mark when the list then adds up', () {
      expect(
        priced([r'1 PUPUSA REVUELTA $1.15 G', r'TOTAL $1.15']),
        ['PUPUSA REVUELTA|1.15'],
      );
      expect(
        priced(['1 TELEVISOR 55 PULG 1,250.00 G', 'TOTAL 1,250.00']),
        ['TELEVISOR 55 PULG|1,250.00'],
      );
      expect(
        priced([
          'AGUA CRISTAL 1.5L  1.15  G',
          'PAN DE CAJA BIMBO  2.85  G',
          'TOTAL 4.00',
        ]),
        ['AGUA CRISTAL 1.5L|1.15', 'PAN DE CAJA BIMBO|2.85'],
      );
      // One row lost its letter.
      expect(
        priced([
          'AGUA CRISTAL 1.5L 1.15 G',
          'PAN DE CAJA BIMBO 2.85',
          'TOTAL 4.00',
        ]),
        ['AGUA CRISTAL 1.5L|1.15', 'PAN DE CAJA BIMBO|2.85'],
      );
      expect(
        priced([
          'AGUA CRISTAL 1.5L 1.15 G',
          'PAN DE CAJA BIMBO 2.85 G',
          'DESCUENTO -0.50',
          'CAFE LISTO 50G 2.10 G',
          'TOTAL 5.60',
        ]),
        [
          'AGUA CRISTAL 1.5L|1.15',
          'PAN DE CAJA BIMBO|2.85',
          'DESCUENTO|-0.50',
          'CAFE LISTO 50G|2.10',
        ],
      );
    });

    test('El Salvador: the sums under the items are not items', () {
      expect(
        priced([
          'AGUA CRISTAL 1.5L 1.15 G',
          'PAN DE CAJA BIMBO 2.85 G',
          'DESCUENTO 0.00',
          'TOTAL 4.00',
        ]),
        ['AGUA CRISTAL 1.5L|1.15', 'PAN DE CAJA BIMBO|2.85'],
      );
      expect(
        priced([
          'AGUA CRISTAL 1.5L 1.15 G',
          'PAN DE CAJA BIMBO 2.85 G',
          'CAFE LISTO 50G 2.10 G',
          'TOTAL GRAVADO 6.10',
          'TOTAL EXENTO 0.00',
          'TOTAL NO SUJETO 0.00',
          'TOTAL 6.10',
        ]),
        [
          'AGUA CRISTAL 1.5L|1.15',
          'PAN DE CAJA BIMBO|2.85',
          'CAFE LISTO 50G|2.10',
        ],
      );
    });

    test('a size written "1.75L" is not a price', () {
      expect(
        read(['COCA COLA 1.75L', '2 x 32.00 64.00', 'TOTAL 64.00']),
        ['2|COCA COLA 1.75L|64.00'],
      );
      expect(
        read(['1 COCA COLA 1.75L 32.00', 'TOTAL 32.00']),
        ['1|COCA COLA 1.75L|32.00'],
      );
    });
  });

  group('round two: rows dated in front', () {
    test('a dated correction or discount stays a line', () {
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          '16/11/26 MINIBAR 85.00',
          '17/11/26 HABITACION 2,150.00',
          '17/11/26 AJUSTE MINIBAR -85.00',
          'TOTAL 4,300.00',
        ]),
        [
          'HABITACION|2,150.00',
          'MINIBAR|85.00',
          'HABITACION|2,150.00',
          'AJUSTE MINIBAR|-85.00',
        ],
      );
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          '17/11/26 HABITACION 2,150.00',
          '17/11/26 DESCUENTO CORPORATIVO -430.00',
          'TOTAL 3,870.00',
        ]),
        [
          'HABITACION|2,150.00',
          'HABITACION|2,150.00',
          'DESCUENTO CORPORATIVO|-430.00',
        ],
      );
    });

    test('undated extras under two dated lines are still listed', () {
      expect(
        priced([
          '24/11/26 TOUR CHICHEN ITZA 2 PAX 3,200.00',
          '25/11/26 TOUR TULUM 2 PAX 2,400.00',
          'TRASLADO AEROPUERTO 600.00',
        ]).last,
        'TRASLADO AEROPUERTO|600.00',
      );
      expect(
        priced([
          '23/11/2026 MEXICO TAPO - PUEBLA CAPU 320.00',
          '25/11/2026 PUEBLA CAPU - MEXICO TAPO 320.00',
          'SEGURO DE VIAJERO 30.00',
          'TOTAL 670.00',
        ]).last,
        'SEGURO DE VIAJERO|30.00',
      );
      expect(
        [
          for (final i in ItemLineParser.extract([
            '16/11/26 HOSPEDAJE 850.00',
            '17/11/26 HOSPEDAJE 850.00',
            'DESAYUNO 2 PAX 240.00',
            'ESTACIONAMIENTO 100.00',
            'TOTAL 2,040.00',
          ]))
            i.amountText,
        ],
        ['850.00', '850.00', '240.00', '100.00'],
      );
    });

    test('payments printed without a minus, and under other names', () {
      for (final payment in [
        '18/11/26 TC VISA 4,300.00',
        '18/11/26 PAGO EN LINEA 4,300.00',
        '18/11/26 DEPOSITO EN GARANTIA 4,300.00',
        '11/18/26 ADVANCE DEPOSIT 4,300.00',
        '11/18/26 DISCOVER 4,300.00',
      ]) {
        expect(
          priced([
            '16/11/26 HABITACION 2,150.00',
            '17/11/26 HABITACION 2,150.00',
            payment,
            'SALDO 0.00',
          ]),
          ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
          reason: payment,
        );
      }
    });

    test('taxes on a night under more labels; totals per day', () {
      for (final tax in [
        'HOTEL/MOTEL TAX 9.45',
        'IMP. HOSP. 3% 64.50',
        'IMP. S/HOSPEDAJE 64.50',
      ]) {
        expect(
          priced([
            '16/11/26 HABITACION 2,150.00',
            '16/11/26 $tax',
            '17/11/26 HABITACION 2,150.00',
            '17/11/26 $tax',
            'TOTAL 4,429.00',
          ]),
          ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
          reason: tax,
        );
      }
      expect(
        priced([
          '16/11/26 HABITACION 2,150.00',
          '16/11/26 RESTAURANTE 485.00',
          'TOTAL DEL DIA 2,635.00',
          '17/11/26 HABITACION 2,150.00',
          '17/11/26 LAVANDERIA 260.00',
          'TOTAL DEL DIA 2,410.00',
          'TOTAL 5,045.00',
        ]),
        [
          'HABITACION|2,150.00',
          'RESTAURANTE|485.00',
          'HABITACION|2,150.00',
          'LAVANDERIA|260.00',
        ],
      );
    });

    test('a night with a percentage on its row is not the lodging tax', () {
      expect(
        [
          for (final i in ItemLineParser.extract([
            'HOSPEDAJE 2 NOCHES 10% DESC 3,870.00',
            'TOTAL 3,870.00',
          ]))
            i.amountText,
        ],
        ['3,870.00'],
      );
    });

    test('dates written year first', () {
      expect(
        priced([
          '2026-11-16 HABITACION 2,150.00',
          '2026-11-16 IVA 16% 344.00',
          '2026-11-17 HABITACION 2,150.00',
          '2026-11-17 IVA 16% 344.00',
          'TOTAL 4,988.00',
        ]),
        ['HABITACION|2,150.00', 'HABITACION|2,150.00'],
      );
    });
  });

  group('round two: totals, taxes and fields', () {
    test('a product named after a payment word', () {
      expect(
        priced([
          'COCA COLA 600ML 18.00',
          'TRANSFERENCIA DE SALDO TELCEL 100.00',
          'SABRITAS 45G 19.00',
          'TOTAL 137.00',
        ]),
        [
          'COCA COLA 600ML|18.00',
          'TRANSFERENCIA DE SALDO TELCEL|100.00',
          'SABRITAS 45G|19.00',
        ],
      );
    });

    test('fuel levies and numbered tax rows are not items', () {
      for (final levy in [
        'I.D.P. Q 40.06',
        'IDP SUPER Q 4.70 X GAL 40.06',
        'IDP (4.70 X GALON) Q 40.06',
      ]) {
        expect(
          priced([
            'SUPER 8.524 31.49 268.42',
            levy,
            'TOTAL Q 268.42',
            'EFECTIVO Q 300.00',
          ]),
          ['SUPER|268.42'],
          reason: levy,
        );
      }
      expect(
        priced([
          'GASOLINA REGULAR 10.000 3.89 38.90',
          'FOVIAL 2.00',
          'COTRANS 1.00',
          'TOTAL 41.90',
        ]),
        ['GASOLINA REGULAR|38.90'],
      );
      expect(
        priced([
          '2 CHEESEBURGER 25.98',
          '1 FRIES 4.50',
          'TAX1 2.51',
          'TOTAL 32.99',
        ]),
        ['CHEESEBURGER|25.98', 'FRIES|4.50'],
      );
    });

    test('savings: a promotion row between items; a card saving at the end',
        () {
      expect(
        priced([
          'SHAMPOO PANTENE 400ML 89.00',
          'SHAMPOO PANTENE 400ML 89.00',
          'AHORRO 2X1 -89.00',
          'PASTA DENTAL COLGATE 45.00',
          'TOTAL 134.00',
        ]).last,
        'PASTA DENTAL COLGATE|45.00',
      );
      expect(
        priced([
          'LECHE SORIANA ENTERA 1L 24.00',
          'PAN BLANCO SORIANA 38.00',
          'AHORRO TARJETA SORIANA -6.00',
          'SUBTOTAL 56.00',
          'TOTAL 56.00',
        ]),
        ['LECHE SORIANA ENTERA 1L|24.00', 'PAN BLANCO SORIANA|38.00'],
      );
    });

    test('fields with the colon lost, and a card voucher underneath', () {
      expect(
        read([
          'PRODUCTO: MAGNA 87 OCT',
          'CANTIDAD: 38.462 LTS',
          r'PRECIO UNITARIO $23.89',
          r'IMPORTE: $918.86',
        ]),
        ['38.462 LTS|MAGNA 87 OCT|918.86'],
      );
      expect(
        read([
          'PRODUCTO MAGNA 87 OCT',
          'CANTIDAD 38.462 LTS',
          r'PRECIO UNITARIO $23.89',
          r'IMPORTE $918.86',
          r'TOTAL $918.86',
        ]),
        ['38.462 LTS|MAGNA 87 OCT|918.86'],
      );
      expect(
        read([
          'PRODUCTO: MAGNA 87 OCT',
          'CANTIDAD: 38.462 LTS',
          r'PRECIO UNITARIO: $23.89',
          r'IMPORTE: $918.86',
          'TARJETA: ************1111',
          'CONCEPTO: VENTA',
          'AUTORIZACION: 123456',
        ]),
        ['38.462 LTS|MAGNA 87 OCT|918.86'],
      );
    });

    test('counts in more wordings', () {
      for (final count in [
        '2 ARTS.',
        'ART. VENDIDOS 2',
        'NRO. ARTICULOS 2',
        '2 ARTICULO(S)',
        'ITEM COUNT 2',
        'UNIDADES VENDIDAS 2',
      ]) {
        expect(
          priced(['1 SHAMPOO 89.00', '1 JABON 22.00', count, 'TOTAL 111.00']),
          ['SHAMPOO|89.00', 'JABON|22.00'],
          reason: count,
        );
      }
    });
  });

  group('round two: names and quantities', () {
    test('a size or number that equals the quantity stays in the name', () {
      expect(
        read(['2 COCA COLA 2 L 30.00 60.00', 'TOTAL 60.00']),
        ['2|COCA COLA 2 L|60.00'],
      );
      expect(
        read(['1 AZUCAR ESTANDAR 1 KG 32.00 32.00', 'TOTAL 32.00']),
        ['1|AZUCAR ESTANDAR 1 KG|32.00'],
      );
      expect(
        read(['2 7501020540666 LECHE LALA 2 L 44.00 88.00', 'TOTAL 88.00']),
        ['2|LECHE LALA 2 L|88.00'],
      );
      expect(
        read([
          '1 COMBO 1 89.00 89.00',
          '2 COMBO 2 99.00 198.00',
          '2 COMBO 3 109.00 218.00',
          'TOTAL 505.00',
        ]),
        ['1|COMBO 1|89.00', '2|COMBO 2|198.00', '2|COMBO 3|218.00'],
      );
    });

    test('the quantity in front and again as "2 x 55.00"', () {
      expect(
        read(['2 CERVEZA CORONA 2 x 55.00 110.00', 'TOTAL 110.00']),
        ['2|CERVEZA CORONA|110.00'],
      );
      expect(
        read(['2 POLAND SPRING WTR 1L 2 @ 2.25 4.50', 'TOTAL 4.50']),
        ['2|POLAND SPRING WTR 1L|4.50'],
      );
      expect(
        read(['3 TACO PASTOR 3 x 22.00 66.00', 'TOTAL 66.00']),
        ['3|TACO PASTOR|66.00'],
      );
    });

    test('"x2" after a barcode is the quantity when the row says so', () {
      expect(
        read(['7501055300075 COCA COLA 600ML x2 18.00 36.00', 'TOTAL 36.00']),
        ['2|COCA COLA 600ML|36.00'],
      );
      expect(
        read([
          '7501055300075 COCA COLA 600ML x2 36.00',
          '7501000111111 GALLETAS MARIAS x1 15.00',
          'TOTAL 51.00',
        ]),
        ['2|COCA COLA 600ML|36.00', '1|GALLETAS MARIAS|15.00'],
      );
    });

    test('a pack size beside a quantity that explains the total', () {
      expect(
        read(['2 CERVEZA CORONA X6 159.00 318.00', 'TOTAL 318.00']),
        ['2|CERVEZA CORONA X6|318.00'],
      );
      expect(
        read(['1 YAKULT X5 45.00 45.00', 'TOTAL 45.00']),
        ['1|YAKULT X5|45.00'],
      );
    });

    test('a quantity with decimals before a dish sold by the litre', () {
      expect(
        read(['2.00 LITRO DE HORCHATA 70.00', 'TOTAL 70.00']),
        ['2|LITRO DE HORCHATA|70.00'],
      );
    });

    test('numbers that climb but multiply out are quantities', () {
      expect(
        read([
          '1 7501055300075 COCA COLA 600ML 18.00 18.00',
          '2 7501000111111 GALLETAS MARIAS 15.00 30.00',
          '3 7501031311309 YOGHURT FRESA 12.00 36.00',
          'TOTAL 84.00',
        ]).map((line) => line.split('|').first),
        ['1', '2', '3'],
      );
      expect(
        read([
          '001 AGUA MINERAL 30.00 30.00',
          '002 TACO PASTOR 22.00 44.00',
          'TOTAL 74.00',
        ]),
        ['1|AGUA MINERAL|30.00', '2|TACO PASTOR|44.00'],
      );
    });

    test('quantity after the name: with a discount column, with decimals',
        () {
      expect(
        read(['PARACETAMOL 500MG 2 45.00 9.00 81.00', 'TOTAL 81.00']),
        ['2|PARACETAMOL 500MG|81.00'],
      );
      expect(
        read(['TACO PASTOR 2.00 22.00 44.00', 'TOTAL 44.00']),
        ['2|TACO PASTOR|44.00'],
      );
    });

    test('a note that begins with a number keeps it', () {
      expect(
        priced(['1 ALITAS 169.00', '10 PIEZAS BBQ', 'TOTAL 169.00']),
        ['ALITAS|169.00', '10 PIEZAS BBQ|'],
      );
    });
  });
}

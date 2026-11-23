import 'package:expense_assistant/domain/logic/item_area_detector.dart';
import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('layouts by kind of shop', () {
    test('convenience store: quantity, name, price; stops at the total', () {
      expect(
        read([
          'OXXO',
          'CADENA COMERCIAL OXXO SA DE CV',
          'RFC XXX010101AB1',
          'TDA 50EJE PLAZA EJEMPLO',
          'AV EJEMPLO 100 COL CENTRO',
          'MONTERREY NL CP 64000',
          '23/11/2026 08:15 CAJA 02',
          'ATENDIO: CAJERO 1',
          '1 COCA COLA 600ML 19.00',
          '1 SABRITAS SAL 45G 18.00',
          '2 AGUA CIEL 1L 28.00',
          'TOTAL 65.00',
          'EFECTIVO 100.00',
          'CAMBIO 35.00',
          'ARTICULOS 4',
          'IVA 16% 8.97',
          'GRACIAS POR SU COMPRA',
        ]),
        ['1|COCA COLA 600ML|19.00', '1|SABRITAS SAL 45G|18.00', '2|AGUA CIEL 1L|28.00'],
      );
    });

    test('supermarket: barcode before the name, tax letter after the price',
        () {
      expect(
        priced([
          'SUPERMERCADO EJEMPLO',
          'TIENDAS EJEMPLO SA DE CV',
          'RFC XXX010101AB1',
          '23/11/26 18:42 TDA 0123 CAJA 07',
          '7501055300075 COCA COLA 600ML 18.00 A',
          '7501000111206 GALLETAS MARIAS 170G 16.50 B',
          '7501020512345 LECHE ENTERA 1L 27.90 B',
          '2050000012345 JAMON DE PAVO 250G 62.00 A',
          'SUBTOTAL 124.40',
          'IVA 11.03',
          'TOTAL 124.40',
          'EFECTIVO 200.00',
          'CAMBIO 75.60',
          'ARTICULOS 4',
        ]),
        [
          'COCA COLA 600ML|18.00',
          'GALLETAS MARIAS 170G|16.50',
          'LECHE ENTERA 1L|27.90',
          'JAMON DE PAVO 250G|62.00',
        ],
      );
    });

    test('US supermarket: code and flags after the name, a weighed line', () {
      expect(
        priced([
          'WALMART',
          'SUPERCENTER',
          'ST# 01234 OP# 001234 TE# 12 TR# 01234',
          'GV WHL MLK 007874235186 F 3.48 O',
          'BREAD 007225003712 F 2.24 O',
          'BANANAS 000000004011 KF',
          '2.36 lb @ 1 lb /0.54 1.27 N',
          'SUBTOTAL 6.99',
          'TAX 1 7.000 % 0.00',
          'TOTAL 6.99',
          'VISA TEND 6.99',
          'CHANGE DUE 0.00',
          '# ITEMS SOLD 3',
          'TC# 0000 0000 0000 0000 0001',
        ]),
        ['GV WHL MLK|3.48', 'BREAD|2.24', 'BANANAS|1.27'],
      );
    });

    test('the name above its "1.00 x 12.35= 12.35E" row', () {
      expect(
        read([
          'EXAMPLE CAFE',
          'TABLE 4',
          'PARIS WARM BOWL',
          '1.00 x 12.35= 12.35E',
          'SPARKLING WATER',
          '2.00 x 2.21= 4.42E',
          'SUBTOTAL 16.77',
        ]),
        ['1|PARIS WARM BOWL|12.35', '2|SPARKLING WATER|4.42'],
      );
    });

    test('unit price and line total with the peso sign read apart', () {
      expect(
        read([
          'CANT. DESCRIPCION PRECIO IMPORTE',
          r'1 VACUNA TRIPLE $ 320.00 $ 320.00',
          r'2 CROQUETAS 2KG $ 157.50 $ 315.00',
          r'TOTAL: $ 635.00',
        ]),
        ['1|VACUNA TRIPLE|320.00', '2|CROQUETAS 2KG|315.00'],
      );
    });

    test('Guatemalan FEL factura in quetzales', () {
      expect(
        read([
          'RESTAURANTE EJEMPLO, S.A.',
          'NIT: 1234567-8',
          'FACTURA',
          'SERIE: ABC12345 NUMERO: 1234567890',
          'NUMERO DE AUTORIZACION:',
          'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
          'FECHA: 23/11/2026',
          'NIT: CF',
          'NOMBRE: CONSUMIDOR FINAL',
          'CANT DESCRIPCION P.UNIT TOTAL',
          '2 DESAYUNO CHAPIN Q45.00 Q90.00',
          '1 CAFE AMERICANO Q 18.00 Q 18.00',
          '1 JUGO DE NARANJA Q22.00 Q22.00',
          'TOTAL Q130.00',
          'SUJETO A PAGOS TRIMESTRALES ISR',
          'CERTIFICADOR: EJEMPLO, S.A. NIT: 7654321-0',
        ]),
        [
          '2|DESAYUNO CHAPIN|90.00',
          '1|CAFE AMERICANO|18.00',
          '1|JUGO DE NARANJA|22.00',
        ],
      );
    });

    test('Salvadoran DTE: "SUMAS" and "VENTAS GRAVADAS" follow the items', () {
      expect(
        read([
          'POLLO EJEMPLO S.A. DE C.V.',
          'NIT: 0000-010101-101-1',
          'NRC: 12345-6',
          'FACTURA',
          'CODIGO DE GENERACION:',
          'XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX',
          'FECHA: 23/11/2026 12:31',
          'CANT DESCRIPCION P.UNIT TOTAL',
          r'1 COMBO 2 PIEZAS $5.99 $5.99',
          r'2 GASEOSA MEDIANA $1.75 $3.50',
          r'1 PIE DE MANZANA $1.25 $1.25',
          r'SUMAS $10.74',
          r'VENTAS GRAVADAS $10.74',
          r'VENTAS EXENTAS $0.00',
          r'VENTAS NO SUJETAS $0.00',
          r'SUB-TOTAL $10.74',
          r'IVA RETENIDO $0.00',
          r'TOTAL A PAGAR $10.74',
        ]),
        ['1|COMBO 2 PIEZAS|5.99', '2|GASEOSA MEDIANA|3.50', '1|PIE DE MANZANA|1.25'],
      );
    });

    test('Venezuelan fiscal printer: quantity row above, tax letter in '
        'brackets, "SUBTTL"', () {
      expect(
        read([
          'SENIAT',
          'RIF J-00000000-0',
          'RESTAURANT EJEMPLO, C.A.',
          'AV. EJEMPLO, CARACAS',
          'FACTURA',
          'FACTURA: 00012345',
          'FECHA: 14/09/2026 HORA: 19:56',
          '2 x Bs 120,00',
          'AREPA REINA PEPIADA (G) Bs 240,00',
          '1 x Bs 45,00',
          'REFRESCO COLA 355ML (G) Bs 45,00',
          '1 x Bs 60,00',
          'AGUA MINERAL 600ML (E) Bs 60,00',
          'SUBTTL Bs 345,00',
          'EXENTO (E) Bs 60,00',
          'BI G (16,00%) Bs 245,69',
          'IVA G (16,00%) Bs 39,31',
          'TOTAL Bs 345,00',
          'EFECTIVO Bs 345,00',
        ]),
        [
          '2|AREPA REINA PEPIADA|240,00',
          '1|REFRESCO COLA 355ML|45,00',
          '1|AGUA MINERAL 600ML|60,00',
        ],
      );
    });

    test('Colombian bill: prices in thousands with no decimals', () {
      expect(
        read([
          'RESTAURANTE EJEMPLO SAS',
          'NIT 900.123.456-7',
          'FACTURA DE VENTA POS No. 12345',
          'FECHA 23/11/2026 13:05',
          'MESA 4',
          'CANT DESCRIPCION VALOR',
          '2 BANDEJA PAISA 64.000',
          '1 LIMONADA DE COCO 9.500',
          '1 CERVEZA CLUB COLOMBIA 8.000',
          'SUBTOTAL 81.500',
          'IMPOCONSUMO 8% 6.037',
          'PROPINA VOLUNTARIA 8.150',
          'TOTAL 95.687',
        ]),
        [
          '2|BANDEJA PAISA|64.000',
          '1|LIMONADA DE COCO|9.500',
          '1|CERVEZA CLUB COLOMBIA|8.000',
        ],
      );
    });

    test('airport shop: the currency code after every price', () {
      expect(
        priced([
          'CAFE EJEMPLO AEROPUERTO T1',
          '23/11/2026 06:40',
          '1 SANDWICH JAMON QUESO 129.00 MXN',
          '1 AGUA NATURAL 600ML 45.00 MXN',
          '1 CAFE LATTE GRANDE 79.00 MXN',
          'TOTAL 253.00 MXN',
          'TARJETA 253.00 MXN',
        ]),
        [
          'SANDWICH JAMON QUESO|129.00',
          'AGUA NATURAL 600ML|45.00',
          'CAFE LATTE GRANDE|79.00',
        ],
      );
    });

    test('US diner: modifiers, a priced add-on, the tip table after the total',
        () {
      expect(
        priced([
          'EXAMPLE DINER',
          '100 EXAMPLE ST, AUSTIN TX 78701',
          '(512) 555-0100',
          'SERVER: ANNA  TABLE 12  GUESTS 2',
          '11/23/2026 12:41 PM  CHECK 1001',
          '1 CHEESEBURGER 12.99',
          'NO ONION',
          'ADD BACON 2.00',
          '1 CAESAR SALAD 9.50',
          'DRESSING ON SIDE',
          '2 ICED TEA 5.98',
          'SUBTOTAL 30.47',
          'TAX 2.51',
          'TOTAL 32.98',
          'SUGGESTED GRATUITY',
          '18% 5.48',
          '20% 6.09',
          '22% 6.70',
          'THANK YOU',
        ]),
        [
          'CHEESEBURGER|12.99',
          'NO ONION|',
          'ADD BACON|2.00',
          'CAESAR SALAD|9.50',
          'DRESSING ON SIDE|',
          'ICED TEA|5.98',
        ],
      );
    });

    test('UK pub: pounds, an optional service charge, VAT under the total',
        () {
      expect(
        priced([
          'THE EXAMPLE ARMS',
          '1 HIGH STREET, LONDON W1 1AA',
          'VAT NO 123 4567 89',
          'TABLE 7  COVERS 2',
          '23/11/2026 19:12',
          '2 FISH & CHIPS £29.90',
          '1 STEAK AND ALE PIE £15.50',
          '2 PINT LAGER £11.60',
          '1 TABLE WATER £0.00',
          'OPTIONAL SERVICE CHARGE 12.5% £7.13',
          'TOTAL £64.13',
          'VAT @ 20% £10.69',
          'CARD £64.13',
        ]),
        [
          'FISH & CHIPS|29.90',
          'STEAK AND ALE PIE|15.50',
          'PINT LAGER|11.60',
          'TABLE WATER|0.00',
        ],
      );
    });

    test('Brazilian snack bar: Portuguese totals with no "subtotal"', () {
      expect(
        priced([
          'LANCHONETE EXEMPLO LTDA',
          'CNPJ 00.000.000/0001-00',
          '23/11/2026 12:10',
          'QTD DESCRICAO VALOR',
          '1 X-BURGER ESPECIAL 25,90',
          '2 SUCO DE LARANJA 18,00',
          '1 AGUA COM GAS 6,00',
          'TAXA DE SERVICO 10% 4,99',
          r'TOTAL R$ 54,89',
          'CARTAO DE CREDITO 54,89',
          'TROCO 0,00',
        ]),
        ['X-BURGER ESPECIAL|25,90', 'SUCO DE LARANJA|18,00', 'AGUA COM GAS|6,00'],
      );
    });

    test('filling station: litres, product, price per litre, amount', () {
      expect(
        read([
          'ESTACION DE SERVICIO EJEMPLO SA DE CV',
          'PERMISO CRE PL/00000/EXP/ES/2016',
          '23/11/2026 07:55 BOMBA 04',
          'CANT PRODUCTO PRECIO IMPORTE',
          '35.214 MAGNA 23.99 844.78',
          'TOTAL 844.78',
        ]),
        ['35.214|MAGNA|844.78'],
      );
      expect(
        read(['BOMBA 04', 'MAGNA 35.214 L x 23.99 844.78', 'TOTAL 844.78']),
        ['35.214 L|MAGNA|844.78'],
      );
    });

    test('weighed goods: the name above "0.450 kg x 34.90/kg  15.71"', () {
      expect(
        read([
          'TOMATE SALADETTE',
          '0.450 kg x 34.90/kg 15.71',
          'AGUACATE HASS',
          '0.620 kg x 89.90/kg 55.74',
          '1 PAN BLANCO BIMBO 48.00',
          'SUBTOTAL 119.45',
        ]),
        [
          '0.450 kg|TOMATE SALADETTE|15.71',
          '0.620 kg|AGUACATE HASS|55.74',
          '1|PAN BLANCO BIMBO|48.00',
        ],
      );
    });
  });

  group('quantities', () {
    const cases = {
      '2x TACO AL PASTOR 44.00': '2|TACO AL PASTOR|44.00',
      '2 X TACO AL PASTOR 44.00': '2|TACO AL PASTOR|44.00',
      '2 x TACO AL PASTOR 44.00': '2|TACO AL PASTOR|44.00',
      'TACO AL PASTOR x2 44.00': '2|TACO AL PASTOR|44.00',
      'TACO AL PASTOR X 2 44.00': '2|TACO AL PASTOR|44.00',
      '2 PZA CONCHA VAINILLA 36.00': '2|CONCHA VAINILLA|36.00',
      '3 PZAS BOLILLO 9.00': '3|BOLILLO|9.00',
      '2.000 UN ARROZ BLANCO 5.00': '2|ARROZ BLANCO|5.00',
      '2 UND EMPANADA DE POLLO 7.00': '2|EMPANADA DE POLLO|7.00',
      '2 × Hamburguesa clásica 378.00': '2|Hamburguesa clásica|378.00',
      '1.00 CAFE AMERICANO 45.00': '1|CAFE AMERICANO|45.00',
      // Name, quantity, unit price, line total: 2 x 22.00 = 44.00.
      'TACO AL PASTOR 2 22.00 44.00': '2|TACO AL PASTOR|44.00',
      '2 TACO AL PASTOR 22.00 44.00': '2|TACO AL PASTOR|44.00',
      // A size is not a quantity: 600 x 18.00 is not 18.00.
      'COCA COLA 600 18.00 18.00': '|COCA COLA 600|18.00',
    };
    cases.forEach((row, expected) {
      test(row, () {
        expect(read([row, 'TOTAL 99.00']), [expected]);
      });
    });
  });

  group('choices, modifiers, combos', () {
    test('choices marked with a dash, an arrow or a plus; a priced extra', () {
      expect(
        priced([
          '1 HAMBURGUESA CLASICA 189.00',
          '- SIN CEBOLLA',
          '- TERMINO MEDIO',
          '+ TOCINO EXTRA 25.00',
          '1 LIMONADA MINERAL 55.00',
          '> SIN HIELO',
          '1 CAFE AMERICANO 45.00',
          '* CON LECHE',
          'SUBTOTAL 314.00',
        ]),
        [
          'HAMBURGUESA CLASICA|189.00',
          'SIN CEBOLLA|',
          'TERMINO MEDIO|',
          'TOCINO EXTRA|25.00',
          'LIMONADA MINERAL|55.00',
          'SIN HIELO|',
          'CAFE AMERICANO|45.00',
          'CON LECHE|',
        ],
      );
    });

    test('a long run of marked modifiers stays with its item', () {
      expect(
        priced([
          '1 HAMBURGUESA DOBLE 219.00',
          '- SIN CEBOLLA',
          '- SIN PEPINILLOS',
          '- SIN MOSTAZA',
          '- EXTRA QUESO',
          '- TERMINO TRES CUARTOS',
          '- PAN SIN AJONJOLI',
          '1 PAPAS GAJO 65.00',
          'TOTAL 284.00',
        ]),
        [
          'HAMBURGUESA DOBLE|219.00',
          'SIN CEBOLLA|',
          'SIN PEPINILLOS|',
          'SIN MOSTAZA|',
          'EXTRA QUESO|',
          'TERMINO TRES CUARTOS|',
          'PAN SIN AJONJOLI|',
          'PAPAS GAJO|65.00',
        ],
      );
    });

    test('a combo whose parts are priced 0.00', () {
      expect(
        read([
          '1 COMBO HAMBURGUESA 159.00',
          '1 HAMBURGUESA SENCILLA 0.00',
          '1 PAPAS MEDIANAS 0.00',
          '1 REFRESCO MEDIANO 0.00',
          '1 CONO VAINILLA 15.00',
          'TOTAL 174.00',
        ]),
        [
          '1|COMBO HAMBURGUESA|159.00',
          '1|HAMBURGUESA SENCILLA|0.00',
          '1|PAPAS MEDIANAS|0.00',
          '1|REFRESCO MEDIANO|0.00',
          '1|CONO VAINILLA|15.00',
        ],
      );
    });

    test('a kiosk meal whose parts have a quantity but no price', () {
      expect(
        priced([
          '1 COMBO HAMBURGUESA GRANDE 139.00',
          '1 HAMBURGUESA CON QUESO',
          '1 PAPAS GRANDES',
          '1 REFRESCO GRANDE',
          'SIN HIELO',
          '1 HELADO VAINILLA 25.00',
          'TOTAL 164.00',
        ]),
        [
          'COMBO HAMBURGUESA GRANDE|139.00',
          'HAMBURGUESA CON QUESO|',
          'PAPAS GRANDES|',
          'REFRESCO GRANDE|',
          'SIN HIELO|',
          'HELADO VAINILLA|25.00',
        ],
      );
    });

    test('a swap of the side dish is a choice, priced or not', () {
      expect(
        priced([
          '1 ARRACHERA 320.00',
          'CAMBIO DE GUARNICION',
          '1 POLLO A LA PLANCHA 210.00',
          'CAMBIO DE GUARNICION 25.00',
          'SUBTOTAL 555.00',
        ]),
        [
          'ARRACHERA|320.00',
          'CAMBIO DE GUARNICION|',
          'POLLO A LA PLANCHA|210.00',
          'CAMBIO DE GUARNICION|25.00',
        ],
      );
    });

    test('a name that wraps after a joining word is one item', () {
      expect(
        priced([
          '1 ENCHILADAS SUIZAS DE 165.00',
          'POLLO CON QUESO',
          '1 AGUA DE HORCHATA 45.00',
          'TOTAL 210.00',
        ]),
        ['ENCHILADAS SUIZAS DE POLLO CON QUESO|165.00', 'AGUA DE HORCHATA|45.00'],
      );
    });
  });

  group('headings, seats and courses are not items or choices', () {
    test('seat and course markers between the dishes', () {
      expect(
        priced([
          'MESA 12 PERS 2',
          'CANT DESCRIPCION IMPORTE',
          'SILLA 1',
          '1 SOPA DE TORTILLA 95.00',
          '1 ARRACHERA 320.00',
          'SILLA 2',
          '1 ENSALADA CESAR 145.00',
          '--- 2do tiempo ---',
          '1 PASTEL DE ELOTE 85.00',
          'BEBIDAS',
          '2 CERVEZA MODELO 110.00',
          'SUBTOTAL 755.00',
        ]),
        [
          'SOPA DE TORTILLA|95.00',
          'ARRACHERA|320.00',
          'ENSALADA CESAR|145.00',
          'PASTEL DE ELOTE|85.00',
          'CERVEZA MODELO|110.00',
        ],
      );
    });

    test('English seat and course markers', () {
      expect(
        priced([
          'SEAT 1',
          '1 TOMATO SOUP 7.50',
          'SEAT 2',
          '1 HOUSE SALAD 8.00',
          '** COURSE 2 **',
          '1 RIBEYE STEAK 34.00',
          'SUBTOTAL 49.50',
        ]),
        ['TOMATO SOUP|7.50', 'HOUSE SALAD|8.00', 'RIBEYE STEAK|34.00'],
      );
    });
  });

  group('discounts and voided lines', () {
    test('a discount between items keeps its sign, also when printed after '
        'the figure', () {
      expect(
        priced([
          '1 CAFE LATTE 68.00',
          '1 CROISSANT 42.00',
          'DESCUENTO EMPLEADO 11.00-',
          '1 JUGO VERDE 55.00',
          'PROMO 2X1 CERVEZA -55.00',
          'TOTAL 99.00',
        ]),
        [
          'CAFE LATTE|68.00',
          'CROISSANT|42.00',
          'DESCUENTO EMPLEADO|-11.00',
          'JUGO VERDE|55.00',
          'PROMO 2X1 CERVEZA|-55.00',
        ],
      );
    });

    test('a cancelled line and the line it cancels are both left out', () {
      expect(
        priced([
          '1 CERVEZA CORONA 55.00',
          '1 TACOS DE ARRACHERA 185.00',
          'CANCELADO 1 CERVEZA CORONA -55.00',
          '1 CERVEZA VICTORIA 55.00',
          'TOTAL 240.00',
        ]),
        ['TACOS DE ARRACHERA|185.00', 'CERVEZA VICTORIA|55.00'],
      );
    });

    test('a void marker above the reversed line', () {
      expect(
        priced([
          'COFFEE LARGE 2.75',
          'MUFFIN BLUEBERRY 3.25',
          '** VOID **',
          'MUFFIN BLUEBERRY 3.25-',
          'BAGEL PLAIN 1.95',
          'TOTAL 4.70',
        ]),
        ['COFFEE LARGE|2.75', 'BAGEL PLAIN|1.95'],
      );
    });
  });

  group('where the list ends', () {
    // The first row under the items on receipts with no "subtotal".
    const totals = [
      'VENTA TOTAL 70.00',
      'GRAN TOTAL 70.00',
      'T O T A L 70.00',
      'IMPORTE TOTAL 70.00',
      'MONTO TOTAL 70.00',
      'VALOR TOTAL 70.00',
      'NETO 60.34',
      'SUMA 70.00',
      'A PAGAR 70.00',
      'TOTAL A PAGAR 70.00',
      '**TOTAL** 70.00',
      r'TOTAL: $70.00',
      'TOTAL MXN 70.00',
      r'TOTAL $ 70.00',
      'TOTAL VENTA 70.00',
      'TOTAL DUE 70.00',
      'AMOUNT DUE 70.00',
      'BALANCE DUE 70.00',
      // The total row as a faint print is read.
      'T0TAL 70.00',
      'TOTAI 70.00',
      'Tota1 S70.OO',
      'SUBT0TAL 70.00',
      'lVA 16% 9.66',
    ];
    for (final row in totals) {
      test('ends at "$row"', () {
        expect(
          priced(['1 CAFE AMERICANO 45.00', '1 PAN DULCE 25.00', row, 'EFECTIVO 100.00']),
          ['CAFE AMERICANO|45.00', 'PAN DULCE|25.00'],
        );
        expect(ItemLineParser.isSummaryRow(row), isTrue);
      });
    }

    // Totals, tax, payment and count rows the list must not take as items.
    const summary = [
      'GRAVADO 60.34',
      'EXENTO 0.00',
      'BASE 60.34',
      'BASE IMPONIBLE 60,34',
      'DESCUENTO TOTAL 7.00',
      'TOTAL DESCUENTOS 7.00',
      'DESCUENTOS 0,00',
      'RECARGOS 0,00',
      'SERVICIO 7.00',
      'CARGO POR SERVICIO 7.00',
      '10% SERVICIO 7.00',
      'PROPINA SUGERIDA 10% 7.00',
      'ANTICIPO 50.00',
      'ABONO 50.00',
      'RECIBIDO 100.00',
      'PAGADO 70.00',
      'SU PAGO 100.00',
      'VUELTO 30.00',
      'CHANGE DUE 30.00',
      'ROUNDING 0.02',
      'ITEMS SOLD 2',
      '# ITEMS SOLD 2',
      'ARTICULOS 2',
      'ARTICULOS VENDIDOS: 2',
      'TOTAL DE ARTICULOS 2',
      'SUMAS 70.00',
      'VENTAS GRAVADAS 70.00',
      'VENTAS EXENTAS 0.00',
      'SUBTTL 70,00',
      'IMPUESTOS 9.66',
      'I.V.A. 16% 9.66',
      '16% IVA 9.66',
      'IGTF 3% 2,10',
      'IMPOCONSUMO 8% 5.60',
      'USTED AHORRO 7.00',
      'MONEDERO ELECTRONICO 5.00',
      'SALES TAX 5.78',
      'VAT @ 20% 11.67',
      'NET 58.33',
      'CASH TENDERED 80.00',
      'TAXA DE SERVICO 10% 7,00',
      'TROCO 5,00',
      'DINHEIRO 80,00',
      'GORJETA 7,00',
      'TIPO DE CAMBIO 17.50',
      'SALDO A PAGAR 70.00',
    ];
    for (final row in summary) {
      test('"$row" is not an item', () {
        expect(
          priced(['1 CAFE AMERICANO 45.00', '1 PAN DULCE 25.00', row, 'TARJETA 70.00']),
          ['CAFE AMERICANO|45.00', 'PAN DULCE|25.00'],
        );
        expect(ItemLineParser.isSummaryRow(row), isTrue);
      });
    }

    // Products whose name begins with, or holds, a word of the totals block.
    const products = {
      'TE VERDE 38.00': 'TE VERDE|38.00',
      'TEA LATTE 4.50': 'TEA LATTE|4.50',
      'DATE SCONE 3.25': 'DATE SCONE|3.25',
      'TIP TOP PAN BLANCO 45.00': 'TIP TOP PAN BLANCO|45.00',
      'TABLE WATER 0.00': 'TABLE WATER|0.00',
      'CASHEW CHICKEN 14.50': 'CASHEW CHICKEN|14.50',
      'CARDAMOM BUN 3.80': 'CARDAMOM BUN|3.80',
      'TAXI AEROPUERTO 350.00': 'TAXI AEROPUERTO|350.00',
      'TARJETA DE REGALO 500.00': 'TARJETA DE REGALO|500.00',
      'MESA DE QUESOS 250.00': 'MESA DE QUESOS|250.00',
      'VINO DE MESA TINTO 95.00': 'VINO DE MESA TINTO|95.00',
      'TOTAL 0% GREEK YOGURT 1.85': 'TOTAL 0% GREEK YOGURT|1.85',
      'COLGATE TOTAL 75ML 45.00': 'COLGATE TOTAL 75ML|45.00',
      'PASTA COLGATE TOTAL 45.00': 'PASTA COLGATE TOTAL|45.00',
      'BASE PARA PIZZA 52.00': 'BASE PARA PIZZA|52.00',
      'SERVICIO A DOMICILIO 35.00': 'SERVICIO A DOMICILIO|35.00',
    };
    products.forEach((row, expected) {
      test('"$row" is an item', () {
        expect(
          priced(['1 CAFE AMERICANO 45.00', row, '1 PAN DULCE 25.00', 'TOTAL 115.00']),
          ['CAFE AMERICANO|45.00', expected, 'PAN DULCE|25.00'],
        );
        expect(ItemLineParser.isSummaryRow(row), isFalse);
      });
    });
  });

  group('rows that only look priced', () {
    test('a card slip has no items', () {
      expect(
        read([
          'BANCO EJEMPLO',
          'VENTA',
          'RESTAURANTE EJEMPLO',
          'AV EJEMPLO 100 CDMX',
          'AFILIACION: 1000001',
          'TARJETA: ************0000',
          'CREDITO/VISA',
          r'MONTO: $635.00',
          r'PROPINA: $63.50',
          r'TOTAL: $698.50',
          'APROBADA AUT. 123456',
          'FIRMA: ____________',
        ]),
        isEmpty,
      );
    });

    test('a parking ticket has no items', () {
      expect(
        read([
          'ESTACIONAMIENTO PLAZA EJEMPLO',
          'BOLETO: 123456',
          'ENTRADA: 23/11/2026 10:15',
          'SALIDA: 23/11/2026 12:40',
          'TIEMPO: 2:25',
          r'TARIFA: $40.00',
          r'IMPORTE: $40.00',
          r'TOTAL $40.00',
        ]),
        isEmpty,
      );
    });

    test('a toll receipt has no items', () {
      expect(
        read([
          'CAMINOS Y PUENTES EJEMPLO',
          'PLAZA DE COBRO 001 EJEMPLO',
          'CARRIL 05 FOLIO 0123456',
          '23/11/2026 10:02:11',
          'CLASE: AUTOMOVIL',
          r'TARIFA: $120.00',
          'IVA INCLUIDO',
          'CONSERVE ESTE COMPROBANTE',
        ]),
        isEmpty,
      );
    });

    test('fuel printed as labelled fields: no "PRECIO" item', () {
      expect(
        read([
          'GASOLINERA EJEMPLO',
          'BOMBA: 04',
          'PRODUCTO: MAGNA',
          'LITROS: 35.214',
          r'PRECIO: $23.99',
          r'IMPORTE: $844.78',
          r'TOTAL: $844.78',
        ]),
        isEmpty,
      );
    });

    test('header rows with a figure that looks like a price', () {
      expect(
        priced([
          'RESTAURANTE EJEMPLO',
          'CARRETERA MEXICO-TOLUCA KM 52.50',
          'TEL 55 1234 56.78',
          'TEL 800 123 45 67',
          'RFC XXX010101AB1',
          'T.C. USD 17.50',
          'MESA 12 PERS 2',
          '23.11.2026 13.44',
          '1 SOPA AZTECA 95.00',
          '1 AGUA MINERAL 45.00',
          'TOTAL 140.00',
        ]),
        ['SOPA AZTECA|95.00', 'AGUA MINERAL|45.00'],
      );
    });

    test('a rule or a half-read QR code under an item is not a choice', () {
      expect(
        priced([
          '1 SOPA AZTECA 95.00',
          '1 AGUA MINERAL 45.00',
          'XX*** X*****',
          '====================',
          'TOTAL 140.00',
        ]),
        ['SOPA AZTECA|95.00', 'AGUA MINERAL|45.00'],
      );
    });
  });

  group('OCR damage', () {
    test('peso sign read as S, O for 0, l for 1, the unit price after @', () {
      expect(
        read([
          'CANT  DESCRIPCION  IMPORTE',
          '3 Salmon S/Mango @S390.  S1,170.00',
          'l Naranjada @S59.OO  \$59.00',
          '1 Paste1 3 Leehes @\$l40  \$140.00',
          '1 Cafe de Olla @\$55.00  \$55.00',
          'Tota1  S1,424.OO',
          'Total de produetos : 6',
        ]),
        [
          '3|Salmon S/Mango|1,170.00',
          '1|Naranjada|59.00',
          '1|Paste1 3 Leehes|140.00',
          '1|Cafe de Olla|55.00',
        ],
      );
    });

    test('a space read inside the price', () {
      expect(
        priced([
          '1 CAFE AMERICANO 45. 00',
          '1 PAN DULCE 25 .00',
          '1 JUGO VERDE 60.OO',
          'TOTAL 130.00',
        ]),
        ['CAFE AMERICANO|45.00', 'PAN DULCE|25.00', 'JUGO VERDE|60.00'],
      );
    });

    test('the price read on the row under its item', () {
      expect(
        read([
          '1 CAFE AMERICANO',
          '45.00',
          '2 PAN DULCE',
          '50.00',
          'TOTAL 95.00',
        ]),
        ['1|CAFE AMERICANO|45.00', '2|PAN DULCE|50.00'],
      );
    });

    test('names read as one block and prices as another are paired in order',
        () {
      expect(
        priced([
          '1 CAFE AMERICANO',
          '1 PAN DULCE',
          '1 JUGO VERDE',
          '45.00',
          '25.00',
          '60.00',
          'TOTAL 130.00',
        ]),
        ['CAFE AMERICANO|45.00', 'PAN DULCE|25.00', 'JUGO VERDE|60.00'],
      );
    });

    test('names and prices that do not pair up are not guessed', () {
      expect(
        priced([
          '1 CAFE AMERICANO',
          '1 PAN DULCE',
          '1 JUGO VERDE',
          '45.00',
          '25.00',
          'TOTAL 130.00',
        ]),
        isEmpty,
      );
    });
  });

  group('item area on the photo', () {
    OcrLine box(String text, double left, double right, int row) => OcrLine(
          text: text,
          left: left,
          top: row * 40.0,
          right: right,
          bottom: row * 40.0 + 26,
        );

    test('covers every item, the choices under them and the totals, past a '
        'printed rule; leaves the header and the footer out', () {
      final lines = [
        box('RESTAURANTE EJEMPLO', 150, 450, 0),
        box('AV EJEMPLO 100 COL CENTRO', 100, 500, 1),
        box('MESA 12 PERS 2', 40, 300, 2),
        box('CANT DESCRIPCION', 40, 330, 3),
        box('IMPORTE', 460, 560, 3),
        box('1 HAMBURGUESA CLASICA', 40, 360, 4),
        box('189.00', 480, 560, 4),
        box('- SIN CEBOLLA', 70, 280, 5),
        box('1 LIMONADA MINERAL', 40, 330, 6),
        box('55.00', 490, 560, 6),
        box('> SIN HIELO', 70, 250, 7),
        box('--------------------------------', 40, 560, 8),
        box('SUBTOTAL', 40, 180, 9),
        box('210.34', 480, 560, 9),
        box('IVA 16%', 40, 160, 10),
        box('33.66', 490, 560, 10),
        box('TOTAL', 40, 140, 11),
        box('244.00', 480, 560, 11),
        box('GRACIAS POR SU VISITA', 120, 480, 13),
        box('www.example.com', 160, 440, 14),
      ];
      final area = ItemAreaDetector.detect(lines)!;
      expect(area.top, greaterThan(3 * 40.0)); // under the column heading
      expect(area.top, lessThanOrEqualTo(4 * 40.0));
      expect(area.bottom, greaterThanOrEqualTo(11 * 40.0 + 26)); // TOTAL
      expect(area.bottom, lessThan(13 * 40.0)); // not the footer
      expect(area.left, lessThanOrEqualTo(40));
      expect(area.right, greaterThanOrEqualTo(560));
    });

    test('a name row and the price row under it are both inside', () {
      final lines = [
        box('EXAMPLE CAFE', 150, 450, 0),
        box('TABLE 4', 40, 200, 1),
        box('PARIS WARM BOWL', 40, 320, 2),
        box('1.00 x 12.35=', 200, 400, 3),
        box('12.35E', 470, 560, 3),
        box('SPARKLING WATER', 40, 320, 4),
        box('2.00 x 2.21=', 200, 400, 5),
        box('4.42E', 480, 560, 5),
        box('SUBTOTAL', 40, 180, 6),
        box('16.77', 480, 560, 6),
      ];
      final area = ItemAreaDetector.detect(lines)!;
      expect(area.top, lessThanOrEqualTo(2 * 40.0));
      expect(area.top, greaterThan(1 * 40.0));
      expect(area.bottom, greaterThanOrEqualTo(6 * 40.0 + 26));
    });

    test('nothing to crop on a card slip', () {
      final lines = [
        box('BANCO EJEMPLO', 150, 450, 0),
        box('VENTA', 250, 350, 1),
        box('AFILIACION: 1000001', 40, 400, 2),
        box('TARJETA: ************0000', 40, 460, 3),
        box(r'MONTO: $635.00', 40, 360, 4),
        box(r'TOTAL: $635.00', 40, 360, 5),
        box('APROBADA AUT. 123456', 40, 400, 6),
      ];
      expect(ItemAreaDetector.detect(lines), isNull);
    });
  });
}

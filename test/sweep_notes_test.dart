import 'package:expense_assistant/domain/logic/receipt_notes.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Good to know" notes over many kinds of receipt: what must be said, and
/// above all what must not be. Every row is one a real till prints (numbers,
/// tax IDs and addresses made generic).

/// Every note as "kind: title", in the order shown.
List<String> shown(List<String> rows) => [
      for (final n in ReceiptNotes.find(rows)) '${n.kind.name}: ${n.title}',
    ];

/// The detail of the one note of [kind].
String detailOf(List<String> rows, String kind) =>
    ReceiptNotes.find(rows).singleWhere((n) => n.kind.name == kind).detail ??
    '';

void main() {
  group('tax invoice: how to request it and by when', () {
    test('convenience store: site, folio, until the last day of the month',
        () {
      const rows = [
        'TOTAL 58.00',
        'EFECTIVO 100.00',
        'CAMBIO 42.00',
        'FACTURACION EN LINEA',
        'www.tienda-example.com/facturacion',
        'TIENES HASTA EL ULTIMO DIA DEL MES',
        'PARA SOLICITAR TU FACTURA',
        'FOLIO: 123456789012',
        'ESTE TICKET NO ES UN COMPROBANTE FISCAL',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within the same month']);
      final detail = detailOf(rows, 'invoice');
      expect(detail, contains('Online: www.tienda-example.com/facturacion'));
      expect(detail, contains('Invoice reference (folio): 123456789012'));
    });

    test('"factura tu ticket en", within the current month, ticket number',
        () {
      const rows = [
        'FACTURA TU TICKET EN:',
        'facturacion.example.com.mx',
        'DENTRO DEL MES EN CURSO',
        'TICKET: 0012345678',
        'TIENDA: 0421',
        'CAJA: 03',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within the same month']);
      final detail = detailOf(rows, 'invoice');
      expect(detail, contains('Online: facturacion.example.com.mx'));
      expect(detail, contains('Invoice reference (folio): 0012345678'));
    });

    test('a deadline in hours; a time of day is not one', () {
      expect(
        shown([
          'SI REQUIERE FACTURA TIENE 72 HORAS',
          'PARA SOLICITARLA EN',
          'www.restaurante-example.mx/factura',
        ]),
        ['invoice: Tax invoice (factura): request it within 72 hours'],
      );
      const bill = [
        'FACTURACION TICKETS DEL MES, DEL DIA',
        'DE CONSUMO Y HASTA LAS 19 HRS DEL ULTIMO',
        'DIA DEL MES.',
        'Obtenga su factura en:',
        'https://www.ejemplo.com/fe/index.aspx',
        'Proporcionando los datos:',
        'Tienda: 5',
        'Ticket: 20260728-001-100001-00001',
      ];
      expect(shown(bill),
          ['invoice: Tax invoice (factura): request it within the same month']);
      expect(detailOf(bill, 'invoice'),
          contains('Invoice reference (folio): 20260728-001-100001-00001'));
    });

    test('an invoice that only becomes available later is not a deadline', () {
      const rows = [
        'TU FACTURA ESTARA DISPONIBLE',
        '24 HRS DESPUES DE TU COMPRA EN',
        'www.farmacia-example.com.mx/facturacion',
      ];
      expect(shown(rows), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(rows, 'invoice'),
          contains('Available 24 hours after the purchase'));
    });

    test('the days for returns are not the invoice deadline, and the other '
        'way round', () {
      expect(
        shown([
          'SOLICITE SU FACTURA EN',
          'www.ropa-example.com.mx',
          'CAMBIOS Y DEVOLUCIONES DENTRO DE',
          'LOS 15 DIAS CON TICKET Y ETIQUETAS',
        ]),
        [
          'invoice: Tax invoice (factura) available',
          'returns: Returns or exchanges within 15 days',
        ],
      );
      expect(
        shown([
          'CAMBIOS UNICAMENTE DENTRO DE LOS',
          '7 DIAS POSTERIORES A SU COMPRA.',
          'FACTURACION: CUENTA CON 30 DIAS',
          'NATURALES A PARTIR DE SU COMPRA',
          'www.muebles-example.com/facturacion',
        ]),
        [
          'invoice: Tax invoice (factura): request it within 30 days',
          'returns: Returns or exchanges within 7 days',
        ],
      );
    });

    test('only on the day of purchase; before the end of the month', () {
      expect(
        shown([
          'FACTURACION UNICAMENTE EL DIA',
          'DE LA COMPRA EN EL RESTAURANTE',
        ]),
        ['invoice: Tax invoice (factura): request it on the day of purchase'],
      );
      const rows = [
        'Genera tu factura antes de fin de mes en',
        'www.cafe-example.mx',
        'Clave de facturacion: 0543 1040 9263 2357',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within the same month']);
      expect(detailOf(rows, 'invoice'),
          contains('Invoice reference (folio): 0543104092632357'));
    });

    test('by e-mail with a code of letters and digits: the e-mail is not a '
        'web site', () {
      const rows = [
        'Solicita tu factura al correo',
        'facturacion@hotel-example.com.mx',
        'Codigo de facturacion: K7HM3PXQ9',
      ];
      expect(shown(rows), ['invoice: Tax invoice (factura) available']);
      final detail = detailOf(rows, 'invoice');
      expect(detail, contains('Invoice help: facturacion@hotel-example.com.mx'));
      expect(detail, contains('Invoice reference (folio): K7HM3PXQ9'));
      expect(detail, isNot(contains('Online:')));
    });

    test('the reference on the row after its label', () {
      const rows = [
        'PARA FACTURAR INGRESE A',
        'www.gasolinera-example.com.mx',
        'CON SU NO. DE REFERENCIA',
        '000123456789',
      ];
      expect(detailOf(rows, 'invoice'),
          contains('Invoice reference (folio): 000123456789'));
    });

    test('read badly: l for I, O for 0, spaces in the address and the folio',
        () {
      const rows = [
        'FACTURAClON EN LlNEA',
        'www. tienda-example. com. mx',
        'CUENTA CON 3O DlAS NATURALES',
        'F0LIO: 0098 7654 3210',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within 30 days']);
      final detail = detailOf(rows, 'invoice');
      expect(detail, contains('Online: www.tienda-example.com.mx'));
      expect(detail, contains('Invoice reference (folio): 009876543210'));
    });

    test('letters lost from "factura" (a real scan)', () {
      const rows = [
        'I.V.A INCLUIDO',
        'PUedes SoliCitar tu factua',
        'Datos pra Factuar=',
        'Ticket : 200000001',
        'Tiena  10000',
        'Fecha  16-1 1-2026',
        'REGIMEN FISCAL:  N/A',
      ];
      expect(shown(rows), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(rows, 'invoice'),
          contains('Invoice reference (folio): 200000001'));
    });

    test('each address goes with its own subject', () {
      const rows = [
        'Consulta nuestro aviso de privacidad en',
        'www.example.com.mx/privacidad',
        'Factura electronica:',
        'www.example.com.mx/facturacion',
        'Tu opinion nos importa:',
        'www.example.com.mx/opina',
      ];
      expect(shown(rows), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(rows, 'invoice'),
          contains('Online: www.example.com.mx/facturacion'));
    });

    test('"factura" that is not about getting one says nothing', () {
      // A company name, a receipt number, a document called "invoice".
      expect(
          shown([
            'MANUFACTURAS EJEMPLO SA DE CV',
            'RFC: XXX010101AB1',
            'TOTAL 250.00',
          ]),
          isEmpty);
      expect(
          shown([
            'THE EXAMPLE GRILL',
            'Invoice #: 100234',
            'Table: 7  Guests: 2',
            'Subtotal 42.00',
            'Tax 3.47',
            'Total 45.47',
          ]),
          isEmpty);
      expect(
          shown([
            'CAMBIOS UNICAMENTE CON TICKET O FACTURA',
            'DENTRO DE LOS 30 DIAS',
          ]),
          ['returns: Returns or exchanges within 30 days']);
    });

    test('a survey that asks for the number of the "factura" is a survey', () {
      const rows = [
        'CUENTANOS TU EXPERIENCIA EN',
        'www.encuesta-example.com',
        'INGRESA EL NUMERO DE TU FACTURA Y',
        'RECIBE UN HELADO GRATIS EN TU PROXIMA VISITA',
      ];
      expect(shown(rows),
          ['offer: Answer the survey for something free next visit']);
      expect(detailOf(rows, 'offer'), 'Online: www.encuesta-example.com');
    });

    test('a ticket that says it is not a tax invoice', () {
      for (final line in [
        'ESTE TICKET NO ES FACTURA',
        'ESTE NO ES UN COMPROBANTE FISCAL',
        'DOCUMENTO SIN VALOR FISCAL',
        'NO VALIDO COMO FACTURA',
      ]) {
        final rows = [
          'TOTAL 135.50',
          'EFECTIVO 200.00',
          'CAMBIO 64.50',
          line,
          'GRACIAS POR SU COMPRA',
        ];
        expect(shown(rows), ['invoice: This ticket is not a tax invoice'],
            reason: line);
      }
      // With nothing more than a slogan beside it, that is still the news.
      expect(
        shown([
          'CUENTA',
          'MESA 7',
          '1 PEPIAN Q 65.00',
          'TOTAL Q 65.00',
          'DOCUMENTO NO VALIDO COMO FACTURA',
          'EXIJA SU FACTURA',
        ]),
        ['invoice: This ticket is not a tax invoice'],
      );
    });
  });

  group('a receipt that already is a tax invoice', () {
    const cfdi = [
      'RESTAURANTE EJEMPLO SA DE CV',
      'RFC: XXX010101AB1',
      'REGIMEN FISCAL: 601 GENERAL DE LEY PERSONAS MORALES',
      'FACTURA: A 1234',
      'FOLIO FISCAL:',
      '0A1B2C3D-1111-4222-8333-444455556666',
      'FECHA DE EMISION: 2026-11-23T14:05:11',
      'RECEPTOR: EMPRESA EJEMPLO SA DE CV',
      'RFC: XXX020202AB2',
      'USO CFDI: G03 GASTOS EN GENERAL',
      '1 CONSUMO DE ALIMENTOS 500.00',
      'SUBTOTAL 431.03',
      'IVA 16% 68.97',
      'TOTAL 500.00',
      'FORMA DE PAGO: 04 TARJETA DE CREDITO',
      'SELLO DIGITAL DEL CFDI:',
      'aBcD1234eFgH5678iJkL9012mNoP3456qRsT7890uVwX',
      'ESTE DOCUMENTO ES UNA REPRESENTACION IMPRESA DE UN CFDI',
      'https://verificacfdi.facturaelectronica.sat.gob.mx',
    ];

    test('Mexican CFDI made out to a company', () {
      expect(shown(cfdi), ['invoice: This is already a tax invoice']);
    });

    test('Mexican CFDI made out to the general public', () {
      final rows = [
        for (final r in cfdi)
          if (r.startsWith('RECEPTOR'))
            'RECEPTOR: PUBLICO EN GENERAL'
          else if (r == 'RFC: XXX020202AB2')
            'RFC: XAXX010101000'
          else if (r.startsWith('USO CFDI'))
            'USO CFDI: S01 SIN EFECTOS FISCALES'
          else
            r,
      ];
      expect(shown(rows), ['invoice: Tax invoice without a company tax ID']);
    });

    const fel = [
      'RESTAURANTE EJEMPLO',
      'EJEMPLO, SOCIEDAD ANONIMA',
      'NIT: 1234567-8',
      '6A AVENIDA 10-00 ZONA 10, GUATEMALA',
      'FACTURA',
      'DOCUMENTO TRIBUTARIO ELECTRONICO',
      'SERIE: 1A2B3C4D',
      'NUMERO: 1234567890',
      'NUMERO DE AUTORIZACION:',
      '1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D',
      'FECHA DE EMISION: 23/11/2026 13:05',
      'NIT: CF',
      'NOMBRE: CONSUMIDOR FINAL',
      'CANT DESCRIPCION TOTAL',
      '1 DESAYUNO CHAPIN Q 45.00',
      '1 CAFE AMERICANO Q 15.00',
      'TOTAL Q 60.00',
      'SUJETO A PAGOS TRIMESTRALES ISR',
      'CERTIFICADOR: EJEMPLO FEL, S.A.',
      'NIT: 7654321-0',
    ];

    test('Guatemalan FEL made out to "CF"', () {
      expect(shown(fel), ['invoice: Tax invoice without a company tax ID']);
    });

    test('Guatemalan FEL with the buyer\'s NIT', () {
      final rows = [
        for (final r in fel)
          if (r == 'NIT: CF')
            'NIT: 9876543-2'
          else if (r.startsWith('NOMBRE'))
            'NOMBRE: EMPRESA EJEMPLO, S.A.'
          else
            r,
      ];
      expect(shown(rows), ['invoice: This is already a tax invoice']);
    });

    test('Salvadoran DTE for a final consumer', () {
      expect(
        shown([
          'SUPER EJEMPLO, S.A. DE C.V.',
          'NIT: 0000-000000-000-0  NRC: 100000-1',
          'DOCUMENTO TRIBUTARIO ELECTRONICO',
          'FACTURA',
          'CODIGO DE GENERACION:',
          'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D',
          'NUMERO DE CONTROL:',
          'DTE-01-M001P001-000000000001234',
          'SELLO DE RECEPCION:',
          '2026A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8',
          'FECHA: 23/11/2026 HORA: 12:10:05',
          'CLIENTE: CONSUMIDOR FINAL',
          '2 AGUA PURA 600ML 1.50',
          r'TOTAL A PAGAR $ 1.50',
        ]),
        ['invoice: Tax invoice without a company tax ID'],
      );
    });

    test('Venezuelan fiscal-printer invoice', () {
      expect(
        shown([
          'SENIAT',
          'RIF: J-00000000-0',
          'INVERSIONES EJEMPLO, C.A.',
          'AV. EJEMPLO, LOCAL 1, CARACAS',
          'RIF/C.I.: J-11111111-1',
          'RAZON SOCIAL: EMPRESA EJEMPLO C.A.',
          'FACTURA',
          'FACTURA: 00012345',
          'FECHA: 23-11-2026 HORA: 13:05',
          '1 x 450,00',
          'PABELLON CRIOLLO (G) Bs 450,00',
          'SUBTTL Bs 450,00',
          'IVA G (16,00%) Bs 72,00',
          'TOTAL Bs 522,00',
          'EFECTIVO Bs 522,00',
          'MH Z1B1234567',
        ]),
        ['invoice: This is already a tax invoice'],
      );
    });

    test('Colombian electronic invoice for a final consumer, voluntary tip '
        'added, amounts without decimals', () {
      expect(
        shown([
          'RESTAURANTE EJEMPLO S.A.S.',
          'NIT 900.000.000-1',
          'FACTURA ELECTRONICA DE VENTA',
          'No. FEV 12345',
          'FECHA: 23/11/2026 13:22',
          'CLIENTE: CONSUMIDOR FINAL',
          'CC/NIT: 222222222222',
          '1 BANDEJA PAISA 45.000',
          '1 AJIACO 28.000',
          '1 LIMONADA DE COCO 12.000',
          'SUBTOTAL 85.000',
          'PROPINA VOLUNTARIA 10% 8.500',
          'TOTAL 93.500',
          'CUFE: 0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f6071',
          'RESOLUCION DIAN 18760000000001',
        ]),
        [
          'invoice: Tax invoice without a company tax ID',
          'tip: Tip on this receipt: 8.500 (10%)',
        ],
      );
    });
  });

  group('not the final receipt', () {
    test('a restaurant pre-bill with a table of suggested tips', () {
      expect(
        shown([
          'RESTAURANTE EJEMPLO',
          '*** PRECUENTA ***',
          'MESA 12 PERSONAS 4',
          '2 ARRACHERA 520.00',
          '4 CERVEZA 280.00',
          'SUBTOTAL 800.00',
          'TOTAL 800.00',
          'PROPINA SUGERIDA',
          '10% 80.00 15% 120.00 20% 160.00',
          'ESTE DOCUMENTO NO ES UN COMPROBANTE FISCAL',
        ]),
        ['preBill: Pre-bill, not the final receipt'],
      );
    });

    test('a Salvadoran table balance (a real scan)', () {
      expect(
        shown([
          'CAFE EJEMPLO',
          'MESA: 20',
          'PREQUENTA',
          'COCA ZERO BOT',
          r'SUBTOTAL $',
          r'PROPINA $',
          'TOTAL',
          '28.23',
          '3.19',
          '31.42',
          'NOTA: ESTE COMPROBANTE "SALDO DE MESA"',
          'NO SUSTITUYE EL TICKET FISCAL.',
          'EXIJA TICKET, FACTURA O CREDITO FISCAL',
        ]),
        ['preBill: Pre-bill, not the final receipt'],
      );
    });

    test('a kitchen order; an order number on a paid ticket is not one', () {
      expect(
        shown([
          '** COMANDA **',
          'MESA 4  MESERO 12',
          '2 TACOS PASTOR',
          '1 AGUA JAMAICA',
          '14:05',
        ]),
        ['preBill: Pre-bill, not the final receipt'],
      );
      expect(
        shown([
          'RESTAURANTE EJEMPLO',
          'MESA 5 COMANDA: 1023',
          '2 ENCHILADAS 180.00',
          'TOTAL 180.00',
          'EFECTIVO 200.00',
          'CAMBIO 20.00',
        ]),
        isEmpty,
      );
    });

    test('a hotel pro-forma', () {
      expect(
        shown([
          'HOTEL EJEMPLO',
          'FACTURA PROFORMA',
          'HABITACION 204',
          '2 NOCHES 3,400.00',
          'TOTAL 3,400.00',
          'DOCUMENTO SIN VALOR FISCAL',
        ]),
        ['preBill: Quote or pro-forma, not a receipt'],
      );
    });
  });

  group('tips', () {
    test('not included, however it is worded or read', () {
      for (final line in [
        'PROPINA NO INCLUIDA',
        'LA PROPINA NO ESTA INCLUIDA',
        'NO SE INCLUYE LA PROPINA',
        'LOS PRECIOS NO INCLUYEN PROPINA',
        'PROPlNA NO lNCLUIDA',
        'EL SERVICIO NO ESTA INCLUIDO',
        'Tips are not included',
        'Service charge is not included',
        'GRATUITY NOT INCLUDED',
      ]) {
        expect(shown([line]), ['tip: Tip not included in the total'],
            reason: line);
      }
    });

    test('included or already added', () {
      for (final rows in [
        ['SERVICIO 10% INCLUIDO'],
        ['INCLUYE 10% DE SERVICIO'],
        ['PROPINA INCLUIDA EN EL TOTAL'],
        ['Service charge included'],
        ['An 18% gratuity has been added to your bill'],
        ['A discretionary service charge of 12.5%', 'has been added to your bill'],
      ]) {
        expect(shown(rows), ['tip: Tip or service already included'],
            reason: '$rows');
      }
    });

    test('what is not a statement about the tip on this bill', () {
      for (final line in [
        'A gratuity of 18% will be added to parties of 6 or more',
        'SERVICIO A DOMICILIO NO INCLUIDO',
        'DESAYUNO INCLUIDO',
        'I.V.A. INCLUIDO',
        'TIPO DE PAGO: TARJETA',
      ]) {
        expect(shown([line]), isEmpty, reason: line);
      }
    });

    test('a tip written in on the card slip, the currency before or after',
        () {
      expect(shown([r'PROPINA: $ 50.00', r'TOTAL: $ 550.00']),
          ['tip: Tip on this receipt: 50.00']);
      expect(shown(['PROPINA 50.00 MXN', 'TOTAL 550.00 MXN']),
          ['tip: Tip on this receipt: 50.00']);
      expect(
          shown([
            r'Total MX$185.50',
            r'Tarifa del viaje MX$165.50',
            r'Propina MX$20.00',
          ]),
          ['tip: Tip on this receipt: 20.00']);
    });

    test('a table of suggested tips and a blank tip line say nothing', () {
      expect(
        shown([
          'Subtotal 50.00',
          'Tax 4.13',
          'Total 54.13',
          'Suggested Gratuity',
          '18% = 9.00',
          '20% = 10.00',
          '22% = 11.00',
          'Tip: ____________',
          'Total: ____________',
        ]),
        isEmpty,
      );
      expect(
        shown([
          r'TOTAL $818.00',
          r'PROPINA SUGERIDA 15% $121.50',
        ]),
        isEmpty,
      );
    });

    test('a tip with a percentage counts when the amounts show it was added',
        () {
      expect(
        shown([
          'Subtotal 70.00',
          'Gratuity 18% 12.60',
          'Tax 5.78',
          'Total 88.38',
        ]),
        ['tip: Tip on this receipt: 12.60 (18%)'],
      );
      // Printed as a hint under the total, not added to anything.
      expect(shown(['TOTAL 450.00', 'PROPINA 10% 45.00']), isEmpty);
    });

    test('a service charge added to the bill', () {
      expect(
        shown([
          'Subtotal £70.00',
          'Service Charge 12.5% £8.75',
          'Total £78.75',
          'A discretionary service charge of 12.5%',
          'has been added to your bill',
        ]),
        ['tip: Service charge on this receipt: 8.75 (12.5%)'],
      );
      expect(
        shown([
          'SUBTTL Bs 522,00',
          '10% SERVICIO Bs 52,20',
          'TOTAL Bs 574,20',
        ]),
        ['tip: Service charge on this receipt: 52,20 (10%)'],
      );
    });

    test('voluntary', () {
      expect(shown(['LA PROPINA ES VOLUNTARIA']), ['tip: Tip is voluntary']);
      expect(shown(['PROPINA NO OBLIGATORIA']), ['tip: Tip is voluntary']);
    });
  });

  group('discounts already taken off', () {
    test('what the till says was saved', () {
      for (final line in [
        'USTED AHORRO 23.50',
        r'AHORRO TOTAL: $23.50',
        'You saved 23.50',
        'TOTAL SAVINGS 23.50',
      ]) {
        expect(shown(['TOTAL 180.00', line]),
            ['discount: Savings on this receipt: 23.50'],
            reason: line);
      }
    });

    test('discount lines however they are labelled', () {
      expect(shown(['TOTAL DESCUENTOS -45.00']),
          ['discount: Discount already applied: -45.00']);
      expect(shown(['10% DESC EMPLEADO -15.00']),
          ['discount: Discount already applied: 10% (-15.00)']);
      expect(shown(['CUPON -30.00']),
          ['discount: Discount already applied: -30.00']);
      expect(shown(['DESC. INAPAM 5% 12.50']),
          ['discount: Discount already applied: 5% (-12.50)']);
    });

    test('a column heading, a zero discount and an item sold as a promotion '
        'are not discounts, nor offers', () {
      expect(
        shown([
          'CANT DESCRIPCION P.UNIT DESCUENTO IMPORTE',
          '2 CAFE AMERICANO 45.00 0.00 90.00',
          'TOTAL 90.00',
        ]),
        isEmpty,
      );
      expect(shown(['DESCUENTO: 0', 'TOTAL 90.00']), isEmpty);
      expect(shown(['DESCUENTO 0.00', 'TOTAL 90.00']), isEmpty);
      expect(
        shown([
          'Base Bs.S41.384,46',
          'Descuentos Bs.S0,00',
          'Recargos Bs.S0,00',
          'Descuentos',
          'Recargos',
          'Sub Total',
          'Impuestos',
        ]),
        isEmpty,
      );
      expect(
        shown([
          'PROMO 2X1 CERVEZA 90.00',
          'PROMOCION DESAYUNO 99.00',
          'TOTAL 189.00',
        ]),
        isEmpty,
      );
    });

    test('a discount promised for next time is an offer, not one applied', () {
      expect(
        shown([r'DESCUENTO 10% EN TU PROXIMA COMPRA MAYOR A $200.00']),
        ['offer: Discount offer: 10% for your next visit'],
      );
    });
  });

  group('offers for next time', () {
    test('words that only look like an offer', () {
      for (final line in [
        'LLAMA GRATIS AL 800 000 0000',
        'LINEA GRATUITA 800 000 0000',
        'TOLL FREE 1-800-000-0000',
        'LO ESPERAMOS EN SU PROXIMA VISITA',
        'PROMOCIONES',
        'DUFRY DUTY FREE',
        'GLUTEN FREE BUN',
        'ENVOLTURA DE REGALO',
        'TICKET DE REGALO',
        'CORTESIA DE LA CASA',
        'PUNTO DE VENTA 0421',
        'NO APLICA CON OTRAS PROMOCIONES',
        'WIFI GRATIS PARA CLIENTES',
      ]) {
        expect(shown([line]), isEmpty, reason: line);
      }
    });

    test('a coupon with its validity', () {
      const rows = [
        'PRESENTA ESTE TICKET Y OBTEN 10% DE',
        'DESCUENTO EN TU PROXIMA COMPRA',
        'VIGENCIA: 31/12/2026',
      ];
      expect(shown(rows), ['offer: Discount offer: 10% for your next visit']);
      expect(detailOf(rows, 'offer'), contains('Valid until: 31/12/2026'));
    });

    test('a free item for coming back', () {
      expect(
        shown([
          'CUPON VALIDO POR UN CAFE AMERICANO',
          'GRATIS EN TU SIGUIENTE VISITA',
        ]),
        ['offer: Free item offer for your next visit'],
      );
    });

    test('two for one', () {
      expect(shown(['MARTES 2X1 EN PIZZAS GRANDES']),
          ['offer: 2x1 promotion']);
    });

    test('points earned and the balance', () {
      const rows = ['PUNTOS ACUMULADOS: 120', 'SALDO DE PUNTOS: 1,540'];
      expect(shown(rows), ['offer: Rewards points']);
      expect(detailOf(rows, 'offer'), 'Accumulated: 120\nBalance: 1,540');
    });

    test('surveys: in English with a free item, with a prize draw', () {
      const english = [
        'Tell us about your visit at',
        'www.example-survey.com',
        'and get a FREE cookie with your next purchase',
      ];
      expect(shown(english),
          ['offer: Answer the survey for something free next visit']);
      expect(detailOf(english, 'offer'), 'Online: www.example-survey.com');
      expect(
        shown([
          'Contesta nuestra encuesta en',
          'www.opina-example.com.mx',
          r'y participa en el sorteo de $10,000',
        ]),
        ['offer: Survey with a prize draw'],
      );
    });
  });

  group('Wi-Fi', () {
    test('the password wherever its label sits', () {
      expect(detailOf(['CLAVE WIFI: cafe2026'], 'wifi'), 'Password: cafe2026');
      expect(detailOf(['Contraseña de wifi: bienvenido1'], 'wifi'),
          'Password: bienvenido1');
      expect(
        detailOf(['WIFI', 'Red: CAFE_EJEMPLO', 'Contraseña: Latte#2026'],
            'wifi'),
        'Network: CAFE_EJEMPLO\nPassword: Latte#2026',
      );
      expect(detailOf(['WIFI: EjemploGuest PW: welcome123'], 'wifi'),
          'Network: EjemploGuest\nPassword: welcome123');
      expect(
        detailOf(['Wi-Fi Network: HOTEL_EJEMPLO', 'Access code: 48213'],
            'wifi'),
        'Network: HOTEL_EJEMPLO\nPassword: 48213',
      );
      expect(
        detailOf(['WIFI: CAFE-EJEMPLO', 'PASSWORD:', 'cafe1234'], 'wifi'),
        'Network: CAFE-EJEMPLO\nPassword: cafe1234',
      );
    });

    test('"internet", "clave" and "pass" about something else', () {
      expect(shown(['COMPRA POR INTERNET', 'CLAVE DE RASTREO: 1234567']),
          isEmpty);
      expect(
          shown([
            'FREE WIFI ON BOARD',
            'PASSENGER RECEIPT',
            'PASS TYPE: ADULT SINGLE',
          ]),
          isEmpty);
      expect(
          shown(['INTERNET 24 HRS 150.00', 'CLAVE DE PRODUCTO: 81112100']),
          isEmpty);
    });
  });

  group('toilet and door codes', () {
    test('a number near a toilet word is a code only when it is given as one',
        () {
      for (final rows in [
        ['AV. BAÑOS DE AGUA SANTA 456 COL. CENTRO'],
        ['PAPEL SANITARIO 400 HOJAS 35.50'],
        [r'USO DE SANITARIOS $7.00', 'FOLIO 004521'],
        ['WC PATO 500ML 39.90'],
        ['ARTICULOS DE ASEO 125.00'],
      ]) {
        expect(shown(rows), isEmpty, reason: '$rows');
      }
    });

    test('codes', () {
      expect(shown(['CODIGO BAÑO: 2580#']), ['toilet: Toilet code: 2580#']);
      expect(shown(['RESTROOM CODE 13579']), ['toilet: Toilet code: 13579']);
      expect(shown(['Clave sanitarios', '4455']),
          ['toilet: Toilet code: 4455']);
      expect(shown(['DOOR CODE: 4521*']), ['toilet: Door code: 4521*']);
    });
  });

  group('returns and warranty', () {
    test('"cambios", "return" and "devolucion" about something else', () {
      for (final rows in [
        ['PRECIOS SUJETOS A CAMBIOS SIN PREVIO AVISO'],
        ['OFF-PEAK RETURN', 'LONDON TERMINALS - EXAMPLE PARKWAY'],
        ['RETURN FLIGHT MEX-GUA'],
        ['CASA DE CAMBIOS EJEMPLO'],
        ['DEVOLUCION', 'TARJETA ************0000', 'IMPORTE 250.00'],
      ]) {
        expect(shown(rows), isEmpty, reason: '$rows');
      }
    });

    test('no returns', () {
      for (final line in [
        'NO SE ACEPTAN CAMBIOS NI DEVOLUCIONES',
        'NO HAY DEVOLUCIONES',
        'ALL SALES FINAL - NO REFUNDS',
        'TARIFA NO REEMBOLSABLE',
      ]) {
        expect(shown([line]), ['returns: No returns or refunds'],
            reason: line);
      }
    });

    test('a window in days or hours, a warranty, a bare policy', () {
      expect(
        shown(['Returns accepted within 90 days', 'with original receipt']),
        ['returns: Returns or exchanges within 90 days'],
      );
      expect(
        shown([
          'CAMBIOS UNICAMENTE DENTRO DE LAS',
          '48 HORAS PRESENTANDO SU TICKET',
        ]),
        ['returns: Returns or exchanges within 48 hours'],
      );
      expect(shown(['GARANTIA: 12 MESES CON ESTE TICKET']),
          ['returns: Warranty: 12 months']);
      expect(shown(['DEVOLUClONES SOLO CON TICKET']),
          ['returns: Returns policy printed on the receipt']);
    });
  });

  group('exchange rate', () {
    test('printed with its rate', () {
      expect(
        shown(['TOTAL USD 25.00', 'TIPO DE CAMBIO 17.25', 'TOTAL MXN 431.25']),
        ['exchangeRate: Exchange rate on the receipt: 17.25'],
      );
      expect(shown(['TASA BCV: 36,50']),
          ['exchangeRate: Exchange rate on the receipt: 36,50']);
      expect(shown(['Tasa del día:Bs.S842,21']),
          ['exchangeRate: Exchange rate on the receipt: 842,21']);
      expect(shown(['EXCHANGE RATE: 1 USD = 17.2500 MXN']),
          ['exchangeRate: Exchange rate on the receipt: 1 USD = 17.2500 MXN']);
    });

    test('"TC" for a transaction code or a credit card is not a rate', () {
      expect(shown(['TC# 1234 5678 9012 3456']), isEmpty);
      expect(shown(['T.C. VISA 250.00']), isEmpty);
    });
  });

  group('parking', () {
    test('validation offered by the shop', () {
      expect(
        shown(['ESTACIONAMIENTO GRATIS 2 HORAS', 'CON SELLO DE CAJA']),
        ['parking: Parking: 2 hours free with validation'],
      );
      expect(
        shown(['SELLA TU BOLETO DE ESTACIONAMIENTO', 'EN CAJA']),
        ['parking: Parking validation available'],
      );
    });

    test('a car park\'s own receipt says nothing', () {
      expect(
        shown([
          'ESTACIONAMIENTO EJEMPLO',
          'ENTRADA 10:05',
          'SALIDA 12:30',
          'TIEMPO 2:25',
          'IMPORTE 48.00',
          'CONSERVE SU BOLETO',
        ]),
        isEmpty,
      );
    });
  });

  group('whole receipts', () {
    /// What the receipt said for the one note of [kind].
    String printedOf(List<String> rows, String kind) =>
        ReceiptNotes.find(rows)
            .singleWhere((n) => n.kind.name == kind)
            .printed ??
        '';

    test('the name or number of an invoice is not an offer of one', () {
      for (final rows in [
        ['FACTURA SERIE A No. 4521', 'FECHA: 23/11/2026'],
        ['FACTURA CONSUMIDOR FINAL', 'No. 000123'],
        ['FACTURA ELECTRONICA', 'TOTAL 250.00'],
        [
          'Factura de venta POS No. 12345',
          'Resolucion DIAN 18764000000001',
          'Autorizacion numeracion de facturacion',
          'del POS 1 al POS 100000',
        ],
        ['TICKET FACTURADO', 'TOTAL 250.00'],
        ['FACTURAR A: EMPRESA EJEMPLO SA DE CV', 'HABITACION 204'],
      ]) {
        expect(shown(rows), isEmpty, reason: '$rows');
      }
    });

    test('a convenience-store ticket: the disclaimer wrapped over two rows, '
        'then how to invoice', () {
      const rows = [
        'TIENDA EJEMPLO',
        'RFC: XXX010101AB1',
        '1 REFRESCO 600ML 18.00',
        r'TOTAL $ 18.00',
        r'EFECTIVO $ 20.00',
        r'CAMBIO $ 2.00',
        'ESTE TICKET NO ES UN',
        'COMPROBANTE FISCAL',
        'FACTURA EN LINEA EN:',
        'www.tienda-example.com/facturacion',
        'ATENCION A CLIENTES 800 000 0000',
        'CONSULTA NUESTRO AVISO DE PRIVACIDAD EN',
        'www.tienda-example.com/privacidad',
      ];
      expect(shown(rows), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(rows, 'invoice'),
          contains('Online: www.tienda-example.com/facturacion'));
      // Without the instructions, the disclaimer is the news.
      expect(shown(rows.sublist(0, 8)),
          ['invoice: This ticket is not a tax invoice']);
      expect(printedOf(rows.sublist(0, 8), 'invoice'),
          'ESTE TICKET NO ES UN COMPROBANTE FISCAL');
      // "0" read for "O" in the one word that turns the sentence round.
      expect(shown(['ESTE TICKET N0 ES UN COMPROBANTE FISCAL']),
          ['invoice: This ticket is not a tax invoice']);
    });

    test('the tax authority\'s and the card terminal\'s sites are not where '
        'the shop invoices', () {
      const rows = [
        'SOLICITA TU CFDI EN',
        'www.tienda-example.mx',
        'VERIFICA TU FACTURA EN www.sat.gob.mx',
        'TIENES 30 DIAS NATURALES',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within 30 days']);
      expect(detailOf(rows, 'invoice'),
          contains('Online: www.tienda-example.mx'));
      expect(
        detailOf(
            ['SOLICITE SU FACTURA EN CAJA', 'COPIA CLIENTE', 'www.clip.mx'],
            'invoice'),
        isNot(contains('Online:')),
      );
    });

    test('when the invoice is sent, and opening hours, are not deadlines', () {
      const sent = [
        'FACTURACION EN:',
        'facturacion.gasolinera-example.com.mx',
        'FOLIO: 1234567',
        'SU FACTURA SE ENVIARA A SU CORREO',
        'DENTRO DE LAS 24 HRS',
      ];
      expect(shown(sent), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(sent, 'invoice'),
          contains('Invoice reference (folio): 1234567'));
      expect(
        shown(['FACTURACION EN SUCURSAL', 'ABIERTO 24 HRS']),
        ['invoice: Tax invoice (factura) available'],
      );
      expect(
        shown([
          'PARA FACTURAR CUENTA CON 24 HRS',
          'facturacion.gasolinera-example.com.mx',
        ]),
        ['invoice: Tax invoice (factura): request it within 24 hours'],
      );
    });

    test('a Mexican restaurant bill: suggested tips, not fiscal, tip not '
        'included', () {
      expect(
        shown([
          'RESTAURANTE EJEMPLO',
          'MESA: 12 PERSONAS: 2',
          '1 ARRACHERA 320.00',
          '2 CERVEZA 140.00',
          'SUBTOTAL: 460.00',
          r'TOTAL: $460.00',
          'PROPINA SUGERIDA',
          '10%: 46.00 15%: 69.00 20%: 92.00',
          'ESTE NO ES UN COMPROBANTE FISCAL',
          'PROPINA N0 INCLUIDA',
          'GRACIAS POR SU VISITA',
          'LO ESPERAMOS PRONTO',
        ]),
        [
          'invoice: This ticket is not a tax invoice',
          'tip: Tip not included in the total',
        ],
      );
    });

    test('a Guatemalan bill that is not the invoice, with the tip added', () {
      expect(
        shown([
          'RESTAURANTE EJEMPLO',
          'MESA 4',
          '2 PEPIAN Q 130.00',
          'SUBTOTAL Q 130.00',
          'PROPINA 10% Q 13.00',
          'TOTAL Q 143.00',
          'ESTE DOCUMENTO NO ES UNA FACTURA',
          'SOLICITE SU FACTURA EN CAJA',
        ]),
        [
          'invoice: Tax invoice (factura) available',
          'tip: Tip on this receipt: 13.00 (10%)',
        ],
      );
    });

    test('a US diner: the large-party gratuity rule is not part of the '
        'survey, nor a tip paid', () {
      const rows = [
        'THE EXAMPLE DINER',
        'Server: 12  Table 4',
        '2 Burger 28.00',
        'Subtotal 28.00',
        'Tax 2.31',
        'Total 30.31',
        'Suggested Gratuity',
        '18% 5.04  20% 5.60  22% 6.16',
        'Tip ________',
        'Total ________',
        '18% gratuity added for parties of 6 or more',
        'Tell us how we did at www.example-diner.com/survey',
        r'for a chance to win a $500 gift card',
        'Returns within 30 days with receipt',
      ];
      expect(shown(rows), [
        'offer: Survey with a prize draw',
        'returns: Returns or exchanges within 30 days',
      ]);
      expect(printedOf(rows, 'offer'), startsWith('Tell us how we did'));
      expect(shown(['PROMO CERVEZA', 'BUY ONE GET ONE FREE']), isEmpty);
    });

    test('a note quotes its own sentence, not the rows that happen to be '
        'above it', () {
      const hotel = [
        'HOTEL EJEMPLO',
        'HABITACION 204',
        'TARIFA NO REEMBOLSABLE',
        'TOTAL USD 250.00',
        'TIPO DE CAMBIO DEL DIA: 17.2500',
        'TOTAL MXN 4,312.50',
        'WIFI: HOTEL_EJEMPLO  PASSWORD: bienvenido',
      ];
      expect(shown(hotel), [
        'exchangeRate: Exchange rate on the receipt: 17.2500',
        'wifi: Wi-Fi password',
        'returns: No returns or refunds',
      ]);
      expect(printedOf(hotel, 'returns'), 'TARIFA NO REEMBOLSABLE');
      expect(detailOf(hotel, 'wifi'),
          'Network: HOTEL_EJEMPLO\nPassword: bienvenido');
      const cafe = [
        'RED WIFI: CAFE_EJEMPLO',
        'CLAVE: cafe2026',
        'BAÑOS: CODIGO 1234',
        'ESTACIONAMIENTO: SELLA TU BOLETO EN CAJA',
      ];
      expect(shown(cafe), [
        'wifi: Wi-Fi password',
        'toilet: Toilet code: 1234',
        'parking: Parking validation available',
      ]);
      expect(detailOf(cafe, 'wifi'),
          'Network: CAFE_EJEMPLO\nPassword: cafe2026');
      expect(printedOf(cafe, 'parking'),
          'ESTACIONAMIENTO: SELLA TU BOLETO EN CAJA');
    });

    test('a pharmacy: savings, points for this purchase, returns refused '
        'only for some goods', () {
      const rows = [
        'FARMACIA EJEMPLO',
        '1 PARACETAMOL 500MG 45.00',
        'TOTAL 45.00',
        r'USTED AHORRO $12.50',
        'PUNTOS ACUMULADOS EN ESTA COMPRA: 4',
        'NO HAY CAMBIOS NI DEVOLUCIONES EN MEDICAMENTOS',
      ];
      expect(shown(rows), [
        'discount: Savings on this receipt: 12.50',
        'offer: Rewards points',
        'returns: Returns policy printed on the receipt',
      ]);
      expect(shown(['NO SE ACEPTAN DEVOLUCIONES SIN TICKET']),
          ['returns: Returns policy printed on the receipt']);
      expect(shown(['TIPO DE CAMBIO: 1.00', 'USTED AHORRO 0.00']), isEmpty);
    });

    test('a card slip and a toll ticket', () {
      expect(
        shown([
          'VENTA',
          'TARJETA ************0000',
          'AUTORIZACION: 123456',
          r'IMPORTE: $ 500.00',
          r'PROPINA: $ 0.00',
          r'TOTAL: $ 500.00',
          'FIRMA ____________',
          'www.clip.mx',
          'COPIA CLIENTE',
        ]),
        isEmpty,
      );
      const toll = [
        'AUTOPISTA EJEMPLO',
        'CASETA EJEMPLO',
        r'IMPORTE $ 98.00',
        'FOLIO 1234567',
        'FACTURE EN www.autopista-example.mx',
        'CONSERVE ESTE COMPROBANTE',
      ];
      expect(shown(toll), ['invoice: Tax invoice (factura) available']);
      expect(detailOf(toll, 'invoice'),
          contains('Online: www.autopista-example.mx'));
    });
  });

  group('wording and misreadings that turn up', () {
    test('an electronic invoice read badly is still one', () {
      expect(
        shown([
          'FACTURA',
          'F0LIO FlSCAL:',
          '0A1B2C3D-1111-4222-8333-444455556666',
          'RECEPTOR: PUBLlCO EN GENERAL',
          'TOTAL 500.00',
        ]),
        ['invoice: Tax invoice without a company tax ID'],
      );
      expect(
        shown([
          'DOCUMENTO TRIBUTARIO ELECTRONIC0',
          'NUMERO DE AUTORIZACI0N:',
          '1A2B3C4D-5E6F-4A8B-9C0D-1E2F3A4B5C6D',
          'NIT: 9876543-2',
          'TOTAL Q 60.00',
        ]),
        ['invoice: This is already a tax invoice'],
      );
    });

    test('a shop\'s own site under the title "FACTURA" is its letterhead', () {
      expect(
        shown([
          'RESTAURANTE EJEMPLO',
          'FACTURA',
          'www.restaurante-example.com.gt',
          'NIT: 1234567-8',
          'TOTAL Q 60.00',
        ]),
        isEmpty,
      );
    });

    test('"autofacturacion", and the month of the purchase', () {
      const rows = [
        'AUTOFACTURACION EN',
        'www.tienda-example.mx',
        'DENTRO DEL MES DE COMPRA',
      ];
      expect(shown(rows),
          ['invoice: Tax invoice (factura): request it within the same month']);
      expect(detailOf(rows, 'invoice'),
          contains('Online: www.tienda-example.mx'));
    });

    test('"cargo por servicio": a percentage that adds up is the service '
        'charge, a bare fee is not a tip', () {
      expect(
        shown([
          'SUBTOTAL 980.00',
          'CARGO POR SERVICIO 10% 98.00',
          'TOTAL 1,078.00',
        ]),
        ['tip: Service charge on this receipt: 98.00 (10%)'],
      );
      expect(
        shown(['BOLETO 450.00', 'CARGO POR SERVICIO 35.00', 'TOTAL 485.00']),
        isEmpty,
      );
    });

    test('a zero that is part of an amount stays a zero', () {
      expect(
        shown(['Subtotal USD9.00', 'Tip USD0.90', 'Total USD9.90']),
        ['tip: Tip on this receipt: 0.90'],
      );
    });

    test('junk never breaks the notes, and never makes a long list', () {
      const bits = [
        'FACTURA', 'FACTURACION', 'PROPINA', 'SERVICIO', '%', '10%', r'$',
        '0.00', '45.00', '-41.50', '1,234.56', '8.500', 'Bs.S', 'WIFI', ':',
        'CLAVE', 'PASSWORD:', '', ' ', 'www.', '.com', '.com.mx', '@',
        'TOTAL', 'SUBTOTAL', '-', '2X1', 'DIAS', '30', '24', 'HRS',
        'GARANTIA', 'CAMBIOS', 'DEVOLUCIONES', 'NO', 'TIPO DE CAMBIO',
        'ESTACIONAMIENTO', 'BAÑO', 'CODIGO', '#', 'PUNTOS', 'GRATIS',
        'PROXIMA VISITA', 'ENCUESTA', 'DESCUENTO', 'CUPON', 'PRECUENTA',
        'SENIAT', 'NIT: CF', 'FOLIO', 'ñ', 'é', '́', '////', '....',
        '()', '[', '*', '+', '?', r'\', '=', '1 USD = ', 'N0', 'l', 'O0O',
      ];
      var seed = 7;
      int next(int n) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % n;
      }

      for (var receipt = 0; receipt < 600; receipt++) {
        final rows = [
          for (var r = next(12); r >= 0; r--)
            [for (var b = next(7); b > 0; b--) bits[next(bits.length)]]
                .join(next(4) == 0 ? '' : ' '),
        ];
        final notes = ReceiptNotes.find(rows);
        expect(notes.length, lessThanOrEqualTo(5), reason: '$rows');
        expect({for (final n in notes) n.kind}.length, notes.length,
            reason: '$rows');
      }
    });
  });

  test('the most important first, and never a long list', () {
    final notes = shown([
      'RESTAURANTE EJEMPLO',
      '1 Desc. 10% -41.50',
      r'Propina $18.65',
      r'Total $392.15',
      'TIPO DE CAMBIO 17.25',
      'WIFI: EJEMPLO Clave: cafe2026',
      'CODIGO BAÑO: 2580#',
      'CAMBIOS Y DEVOLUCIONES DENTRO DE 30 DIAS',
      'PRESENTA ESTE TICKET Y OBTEN 10% DE',
      'DESCUENTO EN TU PROXIMA COMPRA',
      'FACTURACION: CUENTA CON 7 DIAS',
      'www.example.com.mx/facturacion',
    ]);
    expect(notes, [
      'invoice: Tax invoice (factura): request it within 7 days',
      'tip: Tip on this receipt: 18.65',
      'discount: Discount already applied: 10% (-41.50)',
      'exchangeRate: Exchange rate on the receipt: 17.25',
      'offer: Discount offer: 10% for your next visit',
    ]);
  });
}

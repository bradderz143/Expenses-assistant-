import 'dart:io';

import 'package:expense_assistant/application/capture_receipt.dart';
import 'package:expense_assistant/application/package_service.dart';
import 'package:expense_assistant/application/translate_items.dart';
import 'package:expense_assistant/data/db/app_database.dart';
import 'package:expense_assistant/data/repositories/sqlite_repositories.dart';
import 'package:expense_assistant/data/services/file_storage_service.dart';
import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/logic/item_classifier.dart';
import 'package:expense_assistant/domain/logic/receipt_labels.dart';
import 'package:expense_assistant/domain/logic/receipt_text_lines.dart';
import 'package:expense_assistant/domain/logic/text_normaliser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'workflow_test.dart' show FakeOcr, FakePdf, FakeTranslation;

// Receipts that are not meals are translated line by line. Most of their
// lines are a label and its value: the label has a fixed English and the
// value stays as printed. Whole receipts below are as the phone reads them
// row by row (numbers, tax IDs and names made generic).

/// A fuel ticket from a Mexican service station, paid by card.
const fuelTicket = [
  'GASOLINERA LA ESTRELLA SA DE CV',
  'RFC: XXX010101AB1',
  'AV. INSURGENTES SUR 1234 COL. DEL VALLE',
  'C.P. 03100 CIUDAD DE MEXICO',
  'PERMISO CRE: PL/1234/EXP/ES/2015',
  'ESTACION: 4521',
  'FOLIO: 0045213',
  'FECHA: 14/09/2026 HORA: 12:49',
  'BOMBA: 04 MANGUERA: 2',
  'DESPACHADOR: 14',
  'PRODUCTO: MAGNA',
  'LITROS: 35.214',
  'PRECIO POR LITRO: \$23.99',
  'IMPORTE: \$844.78',
  'SUBTOTAL \$728.26',
  'IVA 16% \$116.52',
  'TOTAL \$844.78',
  'OCHOCIENTOS CUARENTA Y CUATRO PESOS 78/100 M.N.',
  'FORMA DE PAGO: TARJETA DE CREDITO',
  'VISA ************1234',
  'AUT: 123456',
  'ESTE TICKET NO ES UN COMPROBANTE FISCAL',
  'FACTURE EN LINEA:',
  'www.ejemplo.mx/factura',
  'GRACIAS POR SU PREFERENCIA',
];

/// A motorway toll ticket (Mexico), paid in cash.
const tollTicket = [
  'CAMINOS Y PUENTES FEDERALES',
  'DE INGRESOS Y SERVICIOS CONEXOS',
  'RFC: XXX010101AB1',
  'PLAZA DE COBRO: 104 TEPOTZOTLAN',
  'AUTOPISTA MEXICO-QUERETARO',
  'CARRIL: 08  CAJERO: 0452',
  'FOLIO: 1234567',
  'FECHA: 14/09/2026  HORA: 10:02:45',
  'CLASE: AUTOMOVIL',
  'EJES: 2',
  'FORMA DE PAGO: EFECTIVO',
  'IMPORTE: \$118.00',
  'IVA INCLUIDO',
  'CONSERVE ESTE COMPROBANTE',
  'PARA FACTURAR INGRESE A',
  'www.ejemplo.gob.mx',
  'BUEN VIAJE',
];

/// A car-park ticket from a shopping centre's pay station.
const parkingTicket = [
  'ESTACIONAMIENTOS EJEMPLO SA DE CV',
  'PLAZA SATELITE',
  'BOLETO: 004521',
  'ENTRADA: 14/09/2026 10:02',
  'SALIDA: 14/09/2026 12:17',
  'TIEMPO: 2:15',
  'TARIFA: \$20.00 POR HORA',
  'TOTAL A PAGAR: \$60.00',
  'EFECTIVO: \$100.00',
  'CAMBIO: \$40.00',
  'CAJERO: 03',
  'ESTE BOLETO NO ES VALIDO COMO FACTURA',
  'LA EMPRESA NO SE HACE RESPONSABLE POR',
  'OBJETOS OLVIDADOS EN SU VEHICULO',
  'GRACIAS POR SU VISITA',
];

/// A prepaid airport taxi ticket.
const taxiTicket = [
  'TAXI SEGURO AEROPUERTO',
  'SITIO 300 AEROPUERTO SA DE CV',
  'RFC XXX010101AB1',
  'BOLETO: 0045213',
  'FECHA 2026-09-18 22:19',
  'ORIGEN: AEROPUERTO T1',
  'DESTINO: ZONA 7 CENTRO',
  'SERVICIO: SEDAN',
  '4 PASAJEROS MAX',
  'TARIFA: \$440.00',
  'FORMA DE PAGO: TARJETA DE DEBITO',
  'UN SOLO DESTINO',
  'BOLETO VIGENTE POR 30 DIAS',
  '220000000000001',
  'www.ejemplo.mx',
  'TEL. 55 5555 0100',
];

/// A hotel folio for six nights: longer than the 40 lines that are kept.
const hotelFolio = [
  'HOTEL CASA BLANCA',
  'OPERADORA HOTELERA EJEMPLO SA DE CV',
  'AV. JUAREZ 45 COL. CENTRO',
  'C.P. 44100 GUADALAJARA, JALISCO',
  'RFC: XXX010101AB1',
  'TEL. 33 5555 0100',
  'FOLIO: 12045',
  'HUESPED: PEREZ JUAN',
  'HABITACION: 204',
  'LLEGADA: 14/09/2026',
  'SALIDA: 20/09/2026',
  'NOCHES: 6',
  'ADULTOS: 1',
  'TARIFA POR NOCHE: 1,850.00',
  'FECHA CONCEPTO CARGOS ABONOS',
  '14/09 HOSPEDAJE 1,850.00',
  '14/09 IVA 16% 296.00',
  '14/09 ISH 3% 55.50',
  '14/09 RESTAURANTE 420.00',
  '15/09 HOSPEDAJE 1,850.00',
  '15/09 IVA 16% 296.00',
  '15/09 ISH 3% 55.50',
  '16/09 HOSPEDAJE 1,850.00',
  '16/09 IVA 16% 296.00',
  '16/09 ISH 3% 55.50',
  '16/09 LAVANDERIA 180.00',
  '17/09 HOSPEDAJE 1,850.00',
  '17/09 IVA 16% 296.00',
  '17/09 ISH 3% 55.50',
  '17/09 SERVICIO A CUARTOS 350.00',
  '18/09 HOSPEDAJE 1,850.00',
  '18/09 IVA 16% 296.00',
  '18/09 ISH 3% 55.50',
  '19/09 HOSPEDAJE 1,850.00',
  '19/09 IVA 16% 296.00',
  '19/09 ISH 3% 55.50',
  '19/09 ESTACIONAMIENTO 150.00',
  'TOTAL CARGOS 14,309.00',
  'TOTAL ABONOS 14,309.00',
  'SALDO: 0.00',
  'FORMA DE PAGO: TARJETA DE CREDITO',
  'VISA ************1234',
  'AUTORIZACION: 123456',
  'FIRMA DEL HUESPED',
  'ACEPTO QUE MI RESPONSABILIDAD POR ESTA CUENTA NO',
  'CESA Y ME OBLIGO A PAGARLA EN CASO DE QUE LA',
  'PERSONA O COMPAÑIA INDICADA NO LO HAGA',
  'ESTE DOCUMENTO NO ES UN COMPROBANTE FISCAL',
  'SOLICITE SU FACTURA EN RECEPCION',
  'CONSULTE NUESTRO AVISO DE PRIVACIDAD EN',
  'www.ejemplo.mx/privacidad',
  'GRACIAS POR SU ESTANCIA',
  'LO ESPERAMOS PRONTO',
];

/// A pharmacy ticket with barcodes before the product names.
const pharmacyTicket = [
  'FARMACIAS EJEMPLO SA DE CV',
  'SUCURSAL: CENTRO',
  'AV. HIDALGO 120 COL. CENTRO',
  'RFC: XXX010101AB1',
  'TICKET: 004521 CAJA: 03',
  'CAJERO: MARIA',
  'FECHA: 14/09/2026 18:22',
  '7501055300075 PARACETAMOL 500MG 20 TABS 45.00',
  '7501055300082 SUERO ORAL 500ML 32.00',
  '7501055300099 CUBREBOCAS 10 PZAS 68.00',
  'ARTICULOS: 3',
  'SUBTOTAL \$145.00',
  'IVA \$0.00',
  'TOTAL \$145.00',
  'EFECTIVO \$200.00',
  'CAMBIO \$55.00',
  'USTED AHORRO: \$12.50',
  'PUNTOS ACUMULADOS: 14',
  'CAMBIOS Y DEVOLUCIONES SOLO CON TICKET',
  'GRACIAS POR SU COMPRA',
  'VUELVA PRONTO',
];

/// A long-distance bus ticket bought at the terminal.
const busTicket = [
  'AUTOBUSES DE ORIENTE EJEMPLO SA DE CV',
  'ORIGEN: MEXICO NORTE',
  'DESTINO: QUERETARO',
  'FECHA DE SALIDA: 14/09/2026',
  'HORA DE SALIDA: 14:30',
  'ASIENTO: 12',
  'PASAJERO: ADULTO',
  'SERVICIO: PRIMERA CLASE',
  'CORRIDA: 4521  ANDEN: 12',
  'TARIFA: \$385.00',
  'IVA INCLUIDO',
  'FORMA DE PAGO: EFECTIVO',
  'FOLIO: 0045213',
  'ESTE BOLETO ES PERSONAL E INTRANSFERIBLE Y',
  'DEBERA PRESENTARSE AL ABORDAR JUNTO CON UNA',
  'IDENTIFICACION OFICIAL VIGENTE.',
  'FACTURACION EN LINEA',
  'www.ejemplo.com.mx',
  'BUEN VIAJE',
];

/// A card-terminal slip from Guatemala.
const guatemalanCardSlip = [
  'FARMACIA EJEMPLO',
  '6A AVENIDA 12-59 ZONA 10',
  'GUATEMALA, GUATEMALA',
  'TERMINAL: 10000001 LOTE: 000123',
  'AFILIACION: 1000001',
  'FECHA: 14/09/2026 HORA: 12:49',
  'VENTA',
  'VISA CREDITO',
  '************1234',
  'AUTORIZACION: 123456',
  'REFERENCIA: 000000001',
  'MONTO: Q 250.00',
  'PROPINA: Q 0.00',
  'TOTAL: Q 250.00',
  'APROBADA',
  'FIRMA:',
  'PAGARE INCONDICIONALMENTE A LA VISTA Y A LA',
  'ORDEN DEL EMISOR DE LA TARJETA EL VALOR',
  'TOTAL DE ESTE PAGARE',
  'COPIA CLIENTE',
];

/// A Guatemalan electronic invoice (FEL) for fuel.
const guatemalanInvoice = [
  'DOCUMENTO TRIBUTARIO ELECTRONICO',
  'FACTURA',
  'COMBUSTIBLES EJEMPLO, SOCIEDAD ANONIMA',
  'ESTACION EJEMPLO',
  'NIT: 1234567-8',
  '7A AVENIDA 3-33 ZONA 9, GUATEMALA',
  'SERIE: A1B2C3D4',
  'NUMERO: 1234567890',
  'NUMERO DE AUTORIZACION:',
  'A1B2C3D4-E5F6-4789-ABCD-0123456789AB',
  'FECHA DE EMISION: 14/09/2026 12:49',
  'NIT: CF',
  'NOMBRE: CONSUMIDOR FINAL',
  'CANTIDAD DESCRIPCION PRECIO TOTAL',
  '10.532 GASOLINA SUPER 32.49 342.18',
  'TOTAL Q 342.18',
  'IDP Q 49.50',
  'IVA 12% Q 31.36',
  'FORMA DE PAGO: EFECTIVO',
  'SUJETO A PAGOS TRIMESTRALES ISR',
  'CERTIFICADOR: CERTIFICADOR EJEMPLO, S.A.',
  'FECHA DE CERTIFICACION: 14/09/2026 12:49:31',
];

/// A Salvadoran electronic invoice (DTE) from a hotel.
const salvadoranInvoice = [
  'DOCUMENTO TRIBUTARIO ELECTRONICO',
  'FACTURA',
  'HOTELES EJEMPLO, S.A. DE C.V.',
  'NIT: 0614-010101-101-0',
  'NRC: 123456-7',
  'BOULEVARD DEL HIPODROMO 110, SAN SALVADOR',
  'CODIGO DE GENERACION:',
  'A1B2C3D4-E5F6-4789-ABCD-0123456789AB',
  'NUMERO DE CONTROL:',
  'DTE-01-M001P001-000000000000123',
  'SELLO DE RECEPCION:',
  '2026A1B2C3D4E5F6A7B8C9D0E1F2A3B4C5D6E7F8',
  'FECHA Y HORA DE GENERACION: 14/09/2026 12:49:05',
  'CLIENTE: JUAN PEREZ',
  'CANT DESCRIPCION PRECIO UNITARIO VENTAS GRAVADAS',
  '2 NOCHE HABITACION SENCILLA 85.00 170.00',
  'SUMAS: \$170.00',
  'VENTAS EXENTAS: \$0.00',
  'VENTAS GRAVADAS: \$170.00',
  'SUBTOTAL: \$170.00',
  'IVA RETENIDO: \$0.00',
  'TOTAL A PAGAR: \$170.00',
  'CIENTO SETENTA 00/100 DOLARES',
  'CONDICION DE LA OPERACION: CONTADO',
];

/// Remembers what was sent to the on-device model.
class _RecordingTranslation extends FakeTranslation {
  final List<String> sent = [];

  @override
  Future<List<String>> translateAll(
    List<String> texts, {
    required String from,
    String to = 'en',
  }) {
    sent.addAll(texts);
    return super.translateAll(texts, from: from, to: to);
  }
}

String? _label(String line) => ReceiptLabels.translate(line, 'es');

void _expectAll(Map<String, String> cases) {
  cases.forEach((spanish, english) {
    expect(_label(spanish), english, reason: spanish);
  });
}

void main() {
  group('label lines: the label in English, the value as printed', () {
    test('dates, tills and ticket numbers', () {
      _expectAll({
        'FECHA: 14/09/2026': 'Date: 14/09/2026',
        'HORA 12:49': 'Time 12:49',
        'FECHA:14/09/2026 HORA:12:49': 'Date: 14/09/2026 Time: 12:49',
        'FECHA 14-SEP-26 HORA 12:49 HRS': 'Date 14-Sep-26 Time 12:49 hrs',
        'FECHA: 14/SEP/2026 12:49': 'Date: 14/Sep/2026 12:49',
        'FECHA/HORA: 14/09/2026 12:49': 'Date and time: 14/09/2026 12:49',
        'FECHA DE EMISION: 14 DE SEPTIEMBRE DE 2026':
            'Issue date: 14 September 2026',
        'FECHA EMISION: 14/09/2026': 'Issue date: 14/09/2026',
        'LUNES 14 DE SEPTIEMBRE DE 2026': 'Monday 14 September 2026',
        'SAB 19 SEP 2026': 'Saturday 19 Sep 2026',
        'CAJERO: MARIA': 'Cashier: MARIA',
        'CAJERO: 12': 'Cashier: 12',
        'CAJA: 03': 'Till: 03',
        'Tienda 15 Caja 1': 'Store 15 Till 1',
        'CAJA 3 TURNO 2': 'Till 3 Shift 2',
        'TICKET: 004521': 'Ticket: 004521',
        'NO. DE TICKET: 409': 'Ticket No.: 409',
        'TICKET No. 4521': 'Ticket No. 4521',
        'NUM. TICKET 4521': 'Ticket No. 4521',
        'FOLIO: 1234567': 'Folio: 1234567',
        'SUCURSAL: CENTRO': 'Branch: CENTRO',
        'LE ATENDIO: MARIA': 'Served by: MARIA',
        'VENDEDOR: 12': 'Salesperson: 12',
        'MESERO: 4 MESA: 12': 'Waiter: 4 Table: 12',
      });
    });

    test('totals, taxes and what was paid', () {
      _expectAll({
        'SUBTOTAL \$145.00': 'Subtotal \$145.00',
        'SUB TOTAL: 491.38': 'Subtotal: 491.38',
        'SUB-TOTAL 491.38': 'Subtotal 491.38',
        'IVA 16%': 'VAT 16%',
        'IVA 16% \$23.20': 'VAT 16% \$23.20',
        'I.V.A. 16% 78.62': 'VAT 16% 78.62',
        'IMPUESTO AL VALOR AGREGADO 16% 78.62': 'VAT 16% 78.62',
        'TOTAL IVA 116.52': 'Total VAT 116.52',
        'IEPS 12.40': 'IEPS (excise tax) 12.40',
        'TOTAL \$168.20': 'Total \$168.20',
        'TOTAL:\$570.00': 'Total: \$570.00',
        'TOTAL MXN \$570.00': 'Total MXN \$570.00',
        'TOTAL: \$ 570.00 MXN': 'Total: \$ 570.00 MXN',
        'TOTAL A PAGAR: \$45.00': 'Total to pay: \$45.00',
        'TOTAL A PAGAR Q 20.00': 'Total to pay Q 20.00',
        'TOTAL M.N.:  300,00': 'Total M.N.: 300,00',
        'IMPORTE: 300,00': 'Amount: 300,00',
        'IMPORTE TOTAL MXN: 570.00': 'Total amount MXN: 570.00',
        'EFECTIVO \$200.00': 'Cash \$200.00',
        'EFECTIVO RECIBIDO 200.00': 'Cash received 200.00',
        'CAMBIO \$31.80': 'Change \$31.80',
        'SU CAMBIO: \$5.00': 'Your change: \$5.00',
        'SU PAGO 200.00': 'Your payment 200.00',
        'IMPORTE PAGADO 200.00': 'Amount paid 200.00',
        'USTED AHORRO: \$12.50': 'You saved: \$12.50',
        'DESCUENTO -15.00': 'Discount -15.00',
        'PROPINA: 0.00': 'Tip: 0.00',
        'PROPINA INCLUIDA: NO': 'Tip included: No',
        'CARGO POR SERVICIO 10% 57.00': 'Service charge 10% 57.00',
        'PUNTOS ACUMULADOS: 16': 'Points earned: 16',
        'ARTICULOS: 3': 'Items: 3',
        'NO. DE ARTICULOS: 3': 'Number of items: 3',
        'TOTAL DE ARTICULOS: 5': 'Total items: 5',
        'ARTICULOS VENDIDOS: 3': 'Items sold: 3',
        'CANT DESCRIPCION PRECIO IMPORTE': 'Qty Description Price Amount',
        'CODIGO DESCRIPCION PRECIO': 'Code Description Price',
        'P.U. \$23.99': 'Unit price \$23.99',
        'TIPO DE CAMBIO: 18.50': 'Exchange rate: 18.50',
        'PAGADO': 'Paid',
      });
    });

    test('how it was paid', () {
      _expectAll({
        'FORMA DE PAGO: EFECTIVO': 'Payment method: Cash',
        'Forma de pago: Efectivo': 'Payment method: Cash',
        'MÉTODO DE PAGO: EFECTIVO': 'Payment method: Cash',
        // The colon the printer left out is put back.
        'FORMA DE PAGO TARJETA DE CREDITO': 'Payment method: Credit card',
        'FORMA DE PAGO: 04 TARJETA DE CREDITO':
            'Payment method: 04 credit card',
        'TIPO DE PAGO: TARJETA DE DEBITO': 'Payment type: Debit card',
        'TIPO PAGO EFECTIVO': 'Payment type: Cash',
        'METODO DE PAGO: PUE PAGO EN UNA SOLA EXHIBICION':
            'Payment method: PUE payment in a single instalment',
        'CONDICION DE PAGO: CONTADO': 'Payment terms: Cash sale (paid in full)',
        'TARJETA DE DEBITO \$168.20': 'Debit card \$168.20',
        'T. CREDITO 570.00': 'Credit card 570.00',
        'TDC VISA ****1234': 'Credit card VISA ****1234',
        'PAGO CON TARJETA DE CREDITO': 'Credit card payment',
        'PAGO EFECTIVO \$200.00': 'Cash payment \$200.00',
        'TOTAL EFECTIVO 200.00': 'Total cash 200.00',
      });
    });

    test('fuel', () {
      _expectAll({
        'BOMBA 4': 'Pump 4',
        'BOMBA: 04 MANGUERA: 2': 'Pump: 04 Hose: 2',
        'ISLA 2 BOMBA 4': 'Island 2 Pump 4',
        'NO. DE BOMBA: 4': 'Pump No.: 4',
        'LITROS 35.214': 'Litres 35.214',
        'LITROS: 35.214': 'Litres: 35.214',
        'CANT. 35.214': 'Qty 35.214',
        'VOLUMEN: 35.214 L': 'Volume: 35.214 L',
        'PRECIO POR LITRO 23.99': 'Price per litre 23.99',
        'PRECIO X LITRO: \$23.99': 'Price per litre: \$23.99',
        'PRODUCTO: MAGNA': 'Product: Regular (Magna)',
        'PRODUCTO: PREMIUM': 'Product: Premium',
        'COMBUSTIBLE: DIESEL': 'Fuel: Diesel',
        '35.214 LTS MAGNA 844.78': '35.214 litres Regular (Magna) 844.78',
        '35.214 LTS x \$23.99': '35.214 litres x \$23.99',
        'GALONES 10.532': 'Gallons 10.532',
        'PRECIO POR GALON Q 32.49': 'Price per gallon Q 32.49',
        'GASOLINA SUPER 10.532 GAL': 'Super petrol 10.532 gallons',
        '10.532 GASOLINA SUPER 32.49 342.18':
            '10.532 super petrol 32.49 342.18',
        'IDP Q 49.50': 'IDP (fuel tax) Q 49.50',
        'DESPACHADOR: 14': 'Attendant: 14',
        'ODOMETRO: 45210': 'Odometer: 45210',
        'PLACAS: ABC-123-D': 'Number plate: ABC-123-D',
        'ESTACION DE SERVICIO 4521': 'Service station 4521',
      });
    });

    test('tolls and car parks', () {
      _expectAll({
        'PLAZA DE COBRO: 104 TEPOTZOTLAN': 'Toll plaza: 104 TEPOTZOTLAN',
        // A place name is kept, never translated ("the sale").
        'CASETA: LA VENTA': 'Toll booth: LA VENTA',
        'CASETA: 12 CARRIL: 08': 'Toll booth: 12 Lane: 08',
        'CLASE: AUTOMOVIL': 'Class: Car',
        'CLASE VEHICULAR: 1': 'Vehicle class: 1',
        'TIPO DE VEHICULO: AUTOMOVIL': 'Vehicle type: Car',
        'EJES: 2': 'Axles: 2',
        'PEAJE \$118.00': 'Toll \$118.00',
        'TRAMO: MEXICO - QUERETARO': 'Section: MEXICO - QUERETARO',
        'CRUCE: 14/09/2026 10:02': 'Crossing: 14/09/2026 10:02',
        'INCLUYE IVA': 'VAT included',
        'IVA INCLUIDO': 'VAT included',
        'BOLETO: 004521': 'Ticket: 004521',
        'TIEMPO: 2:15': 'Duration: 2:15',
        'TIEMPO TRANSCURRIDO: 02:15': 'Length of stay: 02:15',
        'TIEMPO DE ESTANCIA 2 HRS 15 MIN': 'Length of stay 2 hrs 15 min',
        'ESTANCIA: 2 HRS 15 MIN': 'Stay: 2 hrs 15 min',
        'TARIFA: \$20.00 POR HORA': 'Rate: \$20.00 per hour',
        'HORA O FRACCION \$20.00': 'Hour or part of an hour \$20.00',
        'BOLETO PERDIDO \$250.00': 'Lost ticket \$250.00',
        'TOLERANCIA 15 MIN': 'Grace period 15 min',
        'NIVEL: 2': 'Level: 2',
        'PLACA: P-123ABC': 'Number plate: P-123ABC',
        'PARQUEO 2 HORAS Q20.00': 'Parking 2 hrs Q20.00',
      });
    });

    test('taxis, buses and flights', () {
      _expectAll({
        'ORIGEN: AEROPUERTO T1': 'Origin: AEROPUERTO T1',
        'ORIGEN: CIUDAD DE MEXICO': 'Origin: CIUDAD DE MEXICO',
        'DESTINO: ZONA 7 CENTRO': 'Destination: ZONA 7 CENTRO',
        'DESTINO: SAN JUAN DEL RIO': 'Destination: SAN JUAN DEL RIO',
        'SERVICIO: SEDAN': 'Service: SEDAN',
        '4 PASAJEROS MAX': '4 passengers MAX',
        'NO. DE PASAJEROS: 1': 'Number of passengers: 1',
        'UN SOLO DESTINO': 'One destination only',
        'BOLETO VIGENTE POR 30 DIAS': 'Ticket valid for 30 days',
        'CONDUCTOR: 0452': 'Driver: 0452',
        'UNIDAD: 1045': 'Unit: 1045',
        'NO. ECONOMICO: 1045': 'Fleet No.: 1045',
        'DISTANCIA: 12.4 KM': 'Distance: 12.4 KM',
        'TIEMPO DE ESPERA: 5 MIN': 'Waiting time: 5 min',
        'BANDERAZO \$13.10': 'Starting fare \$13.10',
        'TOTAL DEL VIAJE: \$185.00': 'Trip total: \$185.00',
        'TAXI 185.00': 'TAXI 185.00',
        'ASIENTO: 12': 'Seat: 12',
        'FILA 12 ASIENTO C': 'Row 12 Seat C',
        'PASAJERO: ADULTO': 'Passenger: Adult',
        'NOMBRE DEL PASAJERO: PEREZ/JUAN MR': 'Passenger name: PEREZ/JUAN MR',
        'FECHA DE SALIDA: 14/09/2026': 'Departure date: 14/09/2026',
        'HORA DE SALIDA: 14:30': 'Departure time: 14:30',
        'CORRIDA: 4521': 'Service No.: 4521',
        'ANDEN: 12': 'Platform: 12',
        'SERVICIO: PRIMERA CLASE': 'Service: First class',
        'TIPO DE VIAJE: SENCILLO': 'Trip type: One way',
        'VIAJE REDONDO': 'Round trip',
        'BOLETO SENCILLO': 'Ticket: One way',
        '1 ADULTO SENCILLO 385.00': '1 adult one way 385.00',
        'DESCUENTO: 50% ESTUDIANTE': 'Discount: 50% student',
        'VUELO: AM 402': 'Flight: AM 402',
        'PUERTA: 12': 'Gate: 12',
        'TUA 548.00': 'Airport fee (TUA) 548.00',
        'TARIFA AEREA 2,150.00': 'Air fare 2,150.00',
        'CLAVE DE RESERVACION: ABC123': 'Booking reference: ABC123',
      });
    });

    test('hotels', () {
      _expectAll({
        'HABITACION 204': 'Room 204',
        'HABITACION: 204': 'Room: 204',
        'HABITACIÓN: 204': 'Room: 204',
        'HAB. 204': 'Room 204',
        'NUMERO DE HABITACION: 204': 'Room No.: 204',
        'TIPO DE HABITACION: SENCILLA': 'Room type: Single',
        'HABITACION DOBLE': 'Room: Double',
        'HUESPED: PEREZ JUAN': 'Guest: PEREZ JUAN',
        'LLEGADA: 14/09/2026': 'Arrival: 14/09/2026',
        'SALIDA: 16/09/2026': 'Departure: 16/09/2026',
        'CHECK IN: 14/09/2026': 'Check-in: 14/09/2026',
        'ESTANCIA DEL 14/09/2026 AL 16/09/2026':
            'Stay from 14/09/2026 to 16/09/2026',
        'DEL 14/09/2026 AL 16/09/2026': 'From 14/09/2026 to 16/09/2026',
        'NOCHES: 2': 'Nights: 2',
        'NUMERO DE NOCHES: 2': 'Number of nights: 2',
        '2 NOCHES': '2 nights',
        '2 NOCHES x 1,850.00': '2 nights x 1,850.00',
        'ADULTOS: 1': 'Adults: 1',
        'TARIFA POR NOCHE: 1,850.00': 'Nightly rate: 1,850.00',
        'FECHA CONCEPTO CARGOS ABONOS':
            'Date Description Charges Payments on account',
        '14/09 HOSPEDAJE 1,850.00': '14/09 Lodging 1,850.00',
        '14/09 IVA 16% 296.00': '14/09 VAT 16% 296.00',
        '14/09 ISH 3% 55.50': '14/09 Lodging tax 3% 55.50',
        'IMPUESTO SOBRE HOSPEDAJE 55.50': 'Lodging tax 55.50',
        'RESTAURANTE 420.00': 'Restaurant 420.00',
        'SERVICIO A CUARTOS 350.00': 'Room service 350.00',
        'LAVANDERIA 180.00': 'Laundry 180.00',
        'MINIBAR 95.00': 'MINIBAR 95.00',
        'DESAYUNO INCLUIDO': 'Breakfast included',
        'TOTAL CARGOS 2,201.50': 'Total charges 2,201.50',
        'ANTICIPO 1,000.00': 'Advance payment 1,000.00',
        'DEPOSITO 500.00': 'Deposit 500.00',
        'SALDO: 0.00': 'Balance: 0.00',
        'SALDO PENDIENTE 0.00': 'Balance due 0.00',
        'CONFIRMACION: 84512': 'Confirmation: 84512',
        'RESERVACION: 84512': 'Booking: 84512',
        'FIRMA DEL HUESPED': 'Guest signature',
      });
    });

    test('card slips', () {
      _expectAll({
        'TIPO TRANSACCION: VENTA': 'Transaction type: Sale',
        'VENTA': 'Sale',
        'TIPO LECTURA: MSR': 'Card read method: MSR',
        'ACEPTADA': 'Approved',
        'APROBADA': 'Approved',
        'APROBADO EN LINEA': 'Approved online',
        'TRANSACCION APROBADA': 'Transaction approved',
        'OPERACION EXITOSA': 'Transaction successful',
        'CREDITO (1 MESES SIN INTERESES )': 'Credit (1 months interest-free)',
        '3 MESES SIN INTERESES': '3 months interest-free',
        'CUOTAS: 01': 'Instalments: 01',
        'SIN CONTACTO': 'Contactless',
        'VISA': 'VISA',
        'VISA CREDITO': 'VISA credit',
        'MASTERCARD DEBITO': 'MASTERCARD debit',
        'BANCO EMISOR: BBVA': 'Issuing bank: BBVA',
        'MONTO: Q 250.00': 'Amount: Q 250.00',
        'PAGO TARJETA C/TERMINAL': 'Card payment at the terminal',
        'FIRMA DEL TARJETAHABIENTE': 'Cardholder signature',
        'COPIA CLIENTE': 'Customer copy',
        'COPIA COMERCIO': 'Merchant copy',
        'ORIGINAL CLIENTE': 'Customer original',
      });
    });

    test('invoices: Guatemala, El Salvador, Venezuela, Colombia, Mexico', () {
      _expectAll({
        'FACTURA ELECTRONICA': 'Electronic invoice',
        'DOCUMENTO TRIBUTARIO ELECTRONICO': 'Electronic tax document',
        'FACTURA PEQUEÑO CONTRIBUYENTE': "Small taxpayer's invoice",
        'TIPO DE DOCUMENTO: FACTURA': 'Document type: Invoice',
        'FACTURA No. 123': 'Invoice No. 123',
        'SERIE A FOLIO 12345': 'Series A Folio 12345',
        'NIT: CF': 'NIT (tax ID): CF (final consumer)',
        'NIT: 1234567-8': 'NIT (tax ID): 1234567-8',
        'NRC: 123456-7': 'NRC (taxpayer registration): 123456-7',
        'NOMBRE: CONSUMIDOR FINAL': 'Name: Final consumer',
        'CLIENTE: PUBLICO EN GENERAL': 'Customer: General public',
        'FECHA DE CERTIFICACION: 14/09/2026 12:49':
            'Certification date: 14/09/2026 12:49',
        'FECHA Y HORA DE GENERACION: 14/09/2026 12:49:05':
            'Generation date and time: 14/09/2026 12:49:05',
        'MONEDA: GTQ': 'Currency: GTQ',
        'TOTAL Q 250.00': 'Total Q 250.00',
        'IVA 12% Q 26.79': 'VAT 12% Q 26.79',
        'CANTIDAD DESCRIPCION PRECIO TOTAL':
            'Quantity Description Price Total',
        'CONDICION DE LA OPERACION: CONTADO':
            'Terms of sale: Cash sale (paid in full)',
        'SUMAS: \$25.00': 'Sums: \$25.00',
        'VENTAS GRAVADAS: \$25.00': 'Taxable sales: \$25.00',
        'VENTAS EXENTAS: \$0.00': 'Exempt sales: \$0.00',
        'VENTAS NO SUJETAS: \$0.00': 'Non-taxable sales: \$0.00',
        'IVA RETENIDO: \$0.00': 'VAT withheld: \$0.00',
        'BASE IMPONIBLE: Bs. 100,00': 'Taxable base: Bs. 100,00',
        'IGTF 3%: Bs 3,00':
            'IGTF (tax on foreign-currency payments) 3%: Bs 3,00',
        'TASA BCV: 36,50': 'BCV exchange rate: 36,50',
        'Tasa del día:Bs.S842,21': 'Exchange rate of the day: Bs.S842,21',
        'Total sin Servicio  Bs.S48.005,97':
            'Total without service Bs.S48.005,97',
        'VALOR TOTAL: \$ 45.000': 'Total value: \$ 45.000',
        'IMPOCONSUMO 8%: 3.333': 'Consumption tax 8%: 3.333',
      });
    });

    test('letters and digits the scan mixed up, split words, lost letters',
        () {
      _expectAll({
        'T0TAL \$565.00': 'Total \$565.00',
        'TOTAI: 570.00': 'Total: 570.00',
        'TOTA L 570.00': 'Total 570.00',
        'SUBTOTAI 100.00': 'Subtotal 100.00',
        '1VA 16% 78.62': 'VAT 16% 78.62',
        'lMPORTE: 570.00': 'Amount: 570.00',
        'EFECTIV0 100.00': 'Cash 100.00',
        'EFEC TIVO 200.00': 'Cash 200.00',
        'CAJER0: 12': 'Cashier: 12',
        'LITR0S 35.214': 'Litres 35.214',
        'B0MBA 4': 'Pump 4',
        'T1PO DE PAGO: EFECTIV0': 'Payment type: Cash',
        'F0RMA DE PAG0: EFECTIVO': 'Payment method: Cash',
        'FECHA :09/14/2026 19:56:12': 'Date: 09/14/2026 19:56:12',
        'AUTORIZACON: 123456': 'Authorisation: 123456',
        'TRANSACCI NELECTRONICA DE VENTA': 'Electronic sale transaction',
        'Fecha 14.09.2026 Hora 00:17 Ticket10001':
            'Date 14.09.2026 Time 00:17 Ticket 10001',
      });
    });

    test('the dictionary is large and never gives one wording two meanings',
        () {
      expect(ReceiptLabels.selfCheck(), isEmpty);
      expect(ReceiptLabels.size, greaterThan(900));
    });
  });

  group('lines the dictionary must leave alone', () {
    test('what was bought, names, sentences and unknown wording give null',
        () {
      for (final line in [
        // Things bought: for the on-device model.
        '1 COCA COLA 600ML 18.00',
        'PARACETAMOL 500MG 20 TABS 45.00',
        'CAMBIO DE ACEITE 450.00',
        'LAVADO Y PLANCHADO 180.00',
        'PASEO EN LANCHA 500.00',
        'RENTA DE AUTO 3 DIAS 2,400.00',
        'ENTRADA GENERAL 90.00',
        'CUOTA DE RECUPERACION 50.00',
        'SERVICIO DE TAXI AEROPUERTO',
        'DESCRIPCION: SERVICIO DE TAXI',
        'SERVICIO: TAXI AEROPUERTO',
        // Shop and company names, addresses.
        'HOTEL CASA BLANCA',
        'FARMACIAS DEL AHORRO',
        'FARMACIA GUADALAJARA SA DE CV',
        'GASOLINERA LA ESTRELLA',
        'AUTOBUSES DE ORIENTE',
        'TAXI SEGURO AEROPUERTO',
        'AUTOPISTA MEXICO-QUERETARO',
        'AV. REFORMA 222',
        // A person's name with no colon to mark where it starts.
        'CLIENTE JUAN PEREZ',
        'TIPO PAGO: VISA YELLOW CAB',
        // Sentences: standard notices have their own fixed English, the
        // rest goes to the model whole.
        'GRACIAS POR SU COMPRA',
        'CONSERVE SU COMPROBANTE',
        'ESTE BOLETO NO ES VALIDO COMO FACTURA',
        'TOTAL DE ESTE PAGARE',
        'NOTA: NO SE ACEPTAN DEVOLUCIONES',
        // Spanish word order or a joining word that changes the meaning.
        'VENTA CONTADO',
        'IVA Y PROPINA',
        'PAGO A CREDITO',
        'SALDO A FAVOR 12.00',
        'NO PAGADO',
        // A stray letter in front, a row of figures.
        'o Total Bs.S52.144,42',
        '14/09/2026 12:49:05 PM',
      ]) {
        expect(_label(line), isNull, reason: line);
      }
    });

    test('only Spanish receipts are read with the Spanish dictionary', () {
      expect(ReceiptLabels.translate('TOTAL 570.00', 'pt'), isNull);
      expect(ReceiptLabels.translate('DATE: 14/09/2026', 'en'), isNull);
      expect(
        ReceiptLabels.translateAll(['TOTAL 570.00', 'FECHA: 14/09/2026'], 'pt'),
        [null, null],
      );
    });

    test('a value is never dropped or changed', () {
      // "Q" is the currency, not a misprint of the label before it.
      expect(_label('TOTAL A PAGAR Q 20.00'), contains('Q 20.00'));
      expect(_label('HABITACION B'), 'Room B');
      expect(_label('CLASE: A'), 'Class: A');
      // "MAR" before a whole date is Tuesday; beside a day it is March.
      expect(_label('MAR 15/09/2026'), 'Tuesday 15/09/2026');
      expect(_label('15 MAR 2026'), '15 Mar 2026');
      // Every figure of a line is still there, in the same order.
      final figure = RegExp(r'\d[\d.,:/%-]*');
      for (final rows in [fuelTicket, hotelFolio, salvadoranInvoice]) {
        for (final row in rows) {
          final english = _label(row);
          if (english == null) continue;
          expect(
            [for (final m in figure.allMatches(english)) m[0]],
            [for (final m in figure.allMatches(row)) m[0]],
            reason: '$row -> $english',
          );
        }
      }
    });
  });

  group('a caption that means different things on different receipts', () {
    List<String?> all(List<String> lines) =>
        ReceiptLabels.translateAll(lines, 'es');

    test('"SALIDA" is the way out of a car park and the departure of a bus',
        () {
      expect(
        all([
          'ENTRADA: 14/09/2026 10:02',
          'SALIDA: 14/09/2026 12:17',
          'TARIFA: \$20.00 POR HORA',
        ]),
        [
          'Entry: 14/09/2026 10:02',
          'Exit: 14/09/2026 12:17',
          'Rate: \$20.00 per hour',
        ],
      );
      expect(_label('ENTRADA 10:02 SALIDA 12:17'), 'Entry 10:02 Exit 12:17');
      expect(
        all(['SALIDA: 14:30', 'ASIENTO: 12', 'TARIFA: \$385.00']),
        ['Departure: 14:30', 'Seat: 12', 'Fare: \$385.00'],
      );
    });

    test('at a hotel "ENTRADA" and "SALIDA" are check-in and check-out', () {
      expect(
        all([
          'HABITACION: 204',
          'ENTRADA: 14/09/2026',
          'SALIDA: 16/09/2026',
          'TARIFA: 1,850.00',
        ]),
        [
          'Room: 204',
          'Check-in: 14/09/2026',
          'Check-out: 16/09/2026',
          'Rate: 1,850.00',
        ],
      );
    });

    test('"PLAZA" is a toll plaza only on a toll ticket', () {
      expect(
        all(['PLAZA: 104 TEPOTZOTLAN', 'CARRIL: 08']),
        ['Toll plaza: 104 TEPOTZOTLAN', 'Lane: 08'],
      );
      expect(_label('PLAZA: GUADALAJARA'), 'Plaza: GUADALAJARA');
    });
  });

  group('whole receipts: which lines are translated', () {
    test('fuel ticket: product, litres, total and payment; no tax IDs', () {
      final lines = ReceiptTextLines.meaningful(fuelTicket);
      for (final kept in [
        'FECHA: 14/09/2026 HORA: 12:49',
        'PRODUCTO: MAGNA',
        'LITROS: 35.214',
        'PRECIO POR LITRO: \$23.99',
        'IVA 16% \$116.52',
        'TOTAL \$844.78',
        'OCHOCIENTOS CUARENTA Y CUATRO PESOS 78/100 M.N.',
        'FORMA DE PAGO: TARJETA DE CREDITO',
        // The card's brand stays when its number is cut out.
        'VISA',
      ]) {
        expect(lines, contains(kept), reason: kept);
      }
      for (final noise in ['RFC', 'PERMISO', 'AUT:', 'www', '1234']) {
        expect(lines.where((l) => l.startsWith(noise) || l.endsWith(noise)),
            isEmpty,
            reason: noise);
      }
      // A label with nothing after it says nothing.
      expect(lines, isNot(contains('FACTURE EN LINEA:')));
      final printed = ReceiptTextLines.asPrinted(lines);
      expect([for (final i in printed) lines[i]], [
        'GASOLINERA LA ESTRELLA SA DE CV',
        'AV. INSURGENTES SUR 1234 COL. DEL VALLE',
        'C.P. 03100 CIUDAD DE MEXICO',
      ]);
    });

    test('toll ticket: short label lines are never glued together', () {
      final lines = ReceiptTextLines.meaningful(tollTicket);
      expect(
        lines.sublist(lines.indexOf('PLAZA DE COBRO: 104 TEPOTZOTLAN')),
        [
          'PLAZA DE COBRO: 104 TEPOTZOTLAN',
          'AUTOPISTA MEXICO-QUERETARO',
          'CARRIL: 08 CAJERO: 0452',
          'FOLIO: 1234567',
          'FECHA: 14/09/2026 HORA: 10:02:45',
          'CLASE: AUTOMOVIL',
          'EJES: 2',
          'FORMA DE PAGO: EFECTIVO',
          'IMPORTE: \$118.00',
          'IVA INCLUIDO',
          'CONSERVE ESTE COMPROBANTE',
          'PARA FACTURAR INGRESE A',
          'BUEN VIAJE',
        ],
      );
      // The road's name is kept as printed.
      expect(
        ReceiptTextLines.asPrinted(lines),
        contains(lines.indexOf('AUTOPISTA MEXICO-QUERETARO')),
      );
    });

    test('car-park ticket: times and total stay, the wrapped notice is one '
        'sentence again', () {
      final lines = ReceiptTextLines.meaningful(parkingTicket);
      for (final kept in [
        'ENTRADA: 14/09/2026 10:02',
        'SALIDA: 14/09/2026 12:17',
        'TIEMPO: 2:15',
        'TARIFA: \$20.00 POR HORA',
        'TOTAL A PAGAR: \$60.00',
        'EFECTIVO: \$100.00',
        'CAMBIO: \$40.00',
        'GRACIAS POR SU VISITA',
      ]) {
        expect(lines, contains(kept), reason: kept);
      }
      expect(
        lines.where((l) => l.contains('LA EMPRESA NO SE HACE RESPONSABLE POR '
            'OBJETOS OLVIDADOS EN SU VEHICULO')),
        hasLength(1),
      );
      expect(lines, isNot(contains('OBJETOS OLVIDADOS EN SU VEHICULO')));
    });

    test('taxi ticket: no reference number, web address or telephone', () {
      expect(ReceiptTextLines.meaningful(taxiTicket), [
        'TAXI SEGURO AEROPUERTO',
        'SITIO 300 AEROPUERTO SA DE CV',
        'BOLETO: 0045213',
        'FECHA 2026-09-18 22:19',
        'ORIGEN: AEROPUERTO T1',
        'DESTINO: ZONA 7 CENTRO',
        'SERVICIO: SEDAN',
        '4 PASAJEROS MAX',
        'TARIFA: \$440.00',
        'FORMA DE PAGO: TARJETA DE DEBITO',
        'UN SOLO DESTINO',
        'BOLETO VIGENTE POR 30 DIAS',
      ]);
    });

    test('a long hotel folio loses its small print, not its charges, totals '
        'or payment', () {
      final lines = ReceiptTextLines.meaningful(hotelFolio);
      expect(lines, hasLength(40));
      // Every dated charge is there, the tax lines included.
      final charges = [
        for (final row in hotelFolio)
          if (RegExp(r'^\d\d/\d\d ').hasMatch(row)) row,
      ];
      expect(charges, hasLength(22));
      for (final charge in charges) {
        expect(lines, contains(charge), reason: charge);
      }
      for (final kept in [
        'HOTEL CASA BLANCA',
        'HUESPED: PEREZ JUAN',
        'HABITACION: 204',
        'LLEGADA: 14/09/2026',
        'SALIDA: 20/09/2026',
        'TARIFA POR NOCHE: 1,850.00',
        'TOTAL CARGOS 14,309.00',
        'TOTAL ABONOS 14,309.00',
        'SALDO: 0.00',
        'FORMA DE PAGO: TARJETA DE CREDITO',
        'VISA',
      ]) {
        expect(lines, contains(kept), reason: kept);
      }
      // What went: the address, the legal paragraph and the closing notices.
      for (final gone in [
        'AV. JUAREZ 45 COL. CENTRO',
        'C.P. 44100 GUADALAJARA, JALISCO',
        'ESTE DOCUMENTO NO ES UN COMPROBANTE FISCAL',
        'LO ESPERAMOS PRONTO',
      ]) {
        expect(lines, isNot(contains(gone)), reason: gone);
      }
      expect(lines.where((l) => l.startsWith('ACEPTO QUE')), isEmpty);

      // With room for a dozen lines only, the money lines are the ones left.
      final short = ReceiptTextLines.meaningful(hotelFolio, limit: 12);
      expect(short, hasLength(12));
      for (final kept in [
        'TOTAL CARGOS 14,309.00',
        'TOTAL ABONOS 14,309.00',
        'SALDO: 0.00',
        'FORMA DE PAGO: TARJETA DE CREDITO',
      ]) {
        expect(short, contains(kept), reason: kept);
      }
    });

    test('with room to spare the hotel paragraph is one sentence', () {
      final lines = ReceiptTextLines.meaningful(hotelFolio, limit: 60);
      expect(
        lines,
        contains('ACEPTO QUE MI RESPONSABILIDAD POR ESTA CUENTA NO CESA Y ME '
            'OBLIGO A PAGARLA EN CASO DE QUE LA PERSONA O COMPAÑIA INDICADA '
            'NO LO HAGA'),
      );
      // The notices after it are still lines of their own.
      expect(lines, contains('ESTE DOCUMENTO NO ES UN COMPROBANTE FISCAL'));
      expect(lines, contains('GRACIAS POR SU ESTANCIA'));
      expect(lines, contains('LO ESPERAMOS PRONTO'));
    });

    test('pharmacy ticket: a barcode does not hide the product', () {
      final lines = ReceiptTextLines.meaningful(pharmacyTicket);
      for (final kept in [
        '7501055300075 PARACETAMOL 500MG 20 TABS 45.00',
        '7501055300082 SUERO ORAL 500ML 32.00',
        '7501055300099 CUBREBOCAS 10 PZAS 68.00',
        'TICKET: 004521 CAJA: 03',
        'SUBTOTAL \$145.00',
        'TOTAL \$145.00',
        'EFECTIVO \$200.00',
        'CAMBIO \$55.00',
        // Three notices, three lines.
        'CAMBIOS Y DEVOLUCIONES SOLO CON TICKET',
        'GRACIAS POR SU COMPRA',
        'VUELVA PRONTO',
      ]) {
        expect(lines, contains(kept), reason: kept);
      }
      expect(lines.where((l) => l.contains('RFC')), isEmpty);
    });

    test('bus ticket: the conditions wrapped over three rows are one line',
        () {
      final lines = ReceiptTextLines.meaningful(busTicket);
      expect(
        lines,
        contains('ESTE BOLETO ES PERSONAL E INTRANSFERIBLE Y DEBERA '
            'PRESENTARSE AL ABORDAR JUNTO CON UNA IDENTIFICACION OFICIAL '
            'VIGENTE.'),
      );
      for (final kept in [
        'ORIGEN: MEXICO NORTE',
        'DESTINO: QUERETARO',
        'FECHA DE SALIDA: 14/09/2026',
        'HORA DE SALIDA: 14:30',
        'ASIENTO: 12',
        'CORRIDA: 4521 ANDEN: 12',
        'TARIFA: \$385.00',
        'IVA INCLUIDO',
        'FORMA DE PAGO: EFECTIVO',
        'FACTURACION EN LINEA',
        'BUEN VIAJE',
      ]) {
        expect(lines, contains(kept), reason: kept);
      }
      expect(lines.where((l) => l.contains('ejemplo')), isEmpty);
    });

    test('Guatemalan card slip: the amounts stay, the bank references go',
        () {
      final lines = ReceiptTextLines.meaningful(guatemalanCardSlip);
      expect(lines.take(10), [
        'FARMACIA EJEMPLO',
        '6A AVENIDA 12-59 ZONA 10',
        'GUATEMALA, GUATEMALA',
        // Beside "TERMINAL" and "LOTE" there was nothing worth keeping;
        // the date beside nothing at all is.
        'FECHA: 14/09/2026 HORA: 12:49',
        'VENTA',
        'VISA CREDITO',
        'MONTO: Q 250.00',
        'PROPINA: Q 0.00',
        'TOTAL: Q 250.00',
        'APROBADA',
      ]);
      expect(lines, contains('COPIA CLIENTE'));
      // The promissory clause starts one line, whatever the wrapping.
      expect(
        lines.where((l) => l.startsWith(
            'PAGARE INCONDICIONALMENTE A LA VISTA Y A LA ORDEN DEL EMISOR')),
        hasLength(1),
      );
      expect(ReceiptTextLines.asPrinted(lines), containsAll([1, 2]));
    });

    test('Guatemalan electronic invoice: no NIT, series or authorisation '
        'code', () {
      final lines = ReceiptTextLines.meaningful(guatemalanInvoice);
      expect(lines, [
        'DOCUMENTO TRIBUTARIO ELECTRONICO',
        'FACTURA',
        'COMBUSTIBLES EJEMPLO, SOCIEDAD ANONIMA',
        'ESTACION EJEMPLO',
        '7A AVENIDA 3-33 ZONA 9, GUATEMALA',
        'NUMERO: 1234567890',
        'FECHA DE EMISION: 14/09/2026 12:49',
        'NOMBRE: CONSUMIDOR FINAL',
        'CANTIDAD DESCRIPCION PRECIO TOTAL',
        '10.532 GASOLINA SUPER 32.49 342.18',
        'TOTAL Q 342.18',
        'IDP Q 49.50',
        'IVA 12% Q 31.36',
        'FORMA DE PAGO: EFECTIVO',
        'SUJETO A PAGOS TRIMESTRALES ISR',
      ]);
      expect(ReceiptTextLines.asPrinted(lines), {2, 4});
    });

    test('Salvadoran electronic invoice: no generation code or seal', () {
      final lines = ReceiptTextLines.meaningful(salvadoranInvoice);
      expect(lines, [
        'DOCUMENTO TRIBUTARIO ELECTRONICO',
        'FACTURA',
        'HOTELES EJEMPLO, S.A. DE C.V.',
        'BOULEVARD DEL HIPODROMO 110, SAN SALVADOR',
        'FECHA Y HORA DE GENERACION: 14/09/2026 12:49:05',
        'CLIENTE: JUAN PEREZ',
        'CANT DESCRIPCION PRECIO UNITARIO VENTAS GRAVADAS',
        '2 NOCHE HABITACION SENCILLA 85.00 170.00',
        'SUMAS: \$170.00',
        'VENTAS EXENTAS: \$0.00',
        'VENTAS GRAVADAS: \$170.00',
        'SUBTOTAL: \$170.00',
        'IVA RETENIDO: \$0.00',
        'TOTAL A PAGAR: \$170.00',
        'CIENTO SETENTA 00/100 DOLARES',
        'CONDICION DE LA OPERACION: CONTADO',
      ]);
      expect(ReceiptTextLines.asPrinted(lines), {2, 3});
    });

    test('most lines of these receipts never need the on-device model', () {
      // Fixed English (standard wording or the label dictionary) or kept as
      // printed; the model is left with names and things bought.
      const forTheModel = {
        'fuel': <String>[],
        'taxi': ['TAXI SEGURO AEROPUERTO'],
        'pharmacy': [
          '7501055300075 PARACETAMOL 500MG 20 TABS 45.00',
          '7501055300082 SUERO ORAL 500ML 32.00',
          '7501055300099 CUBREBOCAS 10 PZAS 68.00',
        ],
        'Guatemalan invoice': ['ESTACION EJEMPLO'],
      };
      const receipts = {
        'fuel': fuelTicket,
        'taxi': taxiTicket,
        'pharmacy': pharmacyTicket,
        'Guatemalan invoice': guatemalanInvoice,
      };
      receipts.forEach((name, rows) {
        final lines = ReceiptTextLines.meaningful(rows);
        final printed = ReceiptTextLines.asPrinted(lines);
        final labelled = ReceiptLabels.translateAll(lines, 'es');
        expect(
          [
            for (var i = 0; i < lines.length; i++)
              if (KnownPhrases.translate(lines[i], 'es') == null &&
                  labelled[i] == null &&
                  !printed.contains(i))
                lines[i],
          ],
          forTheModel[name],
          reason: name,
        );
      });
    });
  });

  group('choosing and joining lines', () {
    test('a label takes back the value printed under it', () {
      expect(ReceiptTextLines.meaningful(['TOTAL:', '\$570.00']),
          ['TOTAL: \$570.00']);
    });

    test('labels in one block and amounts in another are not paired', () {
      final lines = ReceiptTextLines.meaningful(
          ['SUBTOTAL:', 'IVA:', 'TOTAL:', '491.38', '78.62', '570.00']);
      expect(lines.where((l) => RegExp(r'\d').hasMatch(l)), isEmpty);
    });

    test('of two columns on one row, the reference goes and the date stays',
        () {
      expect(
        ReceiptTextLines.meaningful(['TERMINAL: 12345678 FECHA: 14/09/26']),
        ['FECHA: 14/09/26'],
      );
    });

    test('a date, a rate and an amount around a word do not make the row a '
        'number', () {
      for (final row in [
        '14/09/2026 IVA 16% 296.00',
        '14/09/2026 12:49 ISH 3% 55.50',
        '2026-09-14 HOSPEDAJE 1,850.00',
      ]) {
        expect(ReceiptTextLines.meaningful([row]), [row]);
      }
      // Rows of reference numbers still go.
      expect(ReceiptTextLines.meaningful(['220000000000001']), isEmpty);
      expect(ReceiptTextLines.meaningful(['OP 000123 0045 00012 000987 01']),
          isEmpty);
    });

    test('a masked card number is cut out; rows of stars and crosses go', () {
      expect(ReceiptTextLines.meaningful(['VISA ************1234']), ['VISA']);
      expect(ReceiptTextLines.meaningful(['MASTERCARD DEBITO XXXX-XXXX-1234']),
          ['MASTERCARD DEBITO']);
      expect(ReceiptTextLines.meaningful(['XX*** X*****']), isEmpty);
      expect(ReceiptTextLines.meaningful(['************1234']), isEmpty);
    });

    test('separate notices stay separate lines', () {
      const notices = [
        'GRACIAS POR SU COMPRA',
        'VUELVA PRONTO',
        'CONSERVE SU TICKET',
      ];
      expect(ReceiptTextLines.meaningful(notices), notices);
    });

    test('tax-office boilerplate is not worth a line', () {
      for (final row in [
        'GIRO: VENTA DE COMBUSTIBLES',
        'ACTIVIDAD ECONOMICA: HOTELES',
        'NIT: 1234567-8',
        'NRC: 123456-7',
        'RFC: XXX010101AB1',
        'REGIMEN FISCAL: 601',
      ]) {
        expect(ReceiptTextLines.meaningful([row]), isEmpty, reason: row);
      }
    });
  });

  group('in the app', () {
    late AppDatabase db;
    late Directory temp;
    late FileStorageService storage;
    late FakeOcr ocr;
    late SqliteReceiptRepository receipts;
    late SqliteTranslationRepository translations;
    late SqlitePackageRepository packages;
    late SqliteSettingsRepository settings;
    late PackageService packageService;
    var ids = 0;
    DateTime clock() => DateTime(2026, 11, 23, 9);

    setUpAll(sqfliteFfiInit);

    setUp(() async {
      db = await AppDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      temp = await Directory.systemTemp.createTemp('labels_test');
      storage = FileStorageService(Directory(p.join(temp.path, 'Expenses')));
      await storage.ensureStructure();
      ocr = FakeOcr();
      receipts = SqliteReceiptRepository(db.db);
      translations = SqliteTranslationRepository(db.db);
      packages = SqlitePackageRepository(db.db);
      settings = SqliteSettingsRepository(db.db);
      packageService = PackageService(
        receipts: receipts,
        trips: SqliteTripRepository(db.db),
        translations: translations,
        packages: packages,
        storage: storage,
        pdfRenderer: FakePdf(),
        clock: clock,
      );
    });

    tearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });

    // A fuel ticket with a tin of oil on it.
    const ticket = [
      'GASOLINERA LA ESTRELLA SA DE CV',
      'AV. INSURGENTES SUR 1234 COL. DEL VALLE',
      'RFC: XXX010101AB1',
      'FECHA: 14/09/2026 HORA: 12:49',
      'PRODUCTO: MAGNA',
      'LITROS: 35.214',
      'ACEITE PARA MOTOR 1 LT 189.00',
      'TOTAL \$1,033.78',
      'FORMA DE PAGO: EFECTIVO',
      'VISA ************1234',
      'GRACIAS POR SU PREFERENCIA',
    ];

    test('label lines get the dictionary\'s English; only the rest goes to '
        'the model, and the user\'s own wording wins', () async {
      ocr.enqueueRows(ticket);
      final photo = File(p.join(temp.path, 'fuel.jpg'))
        ..writeAsBytesSync([1, 2, 3]);
      final receipt = (await CaptureReceiptUseCase(
        receipts: receipts,
        trips: SqliteTripRepository(db.db),
        settings: settings,
        storage: storage,
        ocr: ocr,
        translation: FakeTranslation(),
        packages: packageService,
        idGenerator: () => 'id-${++ids}',
        clock: clock,
      )(photo.path))
          .receipt;

      // The user once corrected this line by hand.
      await translations.rememberGlossary(
        'es',
        TextNormaliser.glossaryKey('FORMA DE PAGO: EFECTIVO'),
        'Paid in cash',
      );

      final model = _RecordingTranslation();
      ocr.enqueueRows(ticket);
      final draft = await TranslateItemsUseCase(
        receipts: receipts,
        translations: translations,
        packages: packages,
        packageService: packageService,
        settings: settings,
        storage: storage,
        ocr: ocr,
        translator: model,
        clock: clock,
      ).prepare(
        receipt: receipt,
        croppedImagePath: photo.path,
        mode: TranslationMode.receiptText,
      );

      expect(draft.mode, TranslationMode.receiptText);
      expect(draft.warning, isNull);
      expect(
        {for (final l in draft.lines) l.originalText: l.translatedText},
        {
          // Company name and address: as printed.
          'GASOLINERA LA ESTRELLA SA DE CV': 'GASOLINERA LA ESTRELLA SA DE CV',
          'AV. INSURGENTES SUR 1234 COL. DEL VALLE':
              'AV. INSURGENTES SUR 1234 COL. DEL VALLE',
          // The label dictionary.
          'FECHA: 14/09/2026 HORA: 12:49': 'Date: 14/09/2026 Time: 12:49',
          'PRODUCTO: MAGNA': 'Product: Regular (Magna)',
          'LITROS: 35.214': 'Litres: 35.214',
          'TOTAL \$1,033.78': 'Total \$1,033.78',
          'VISA': 'VISA',
          // Something bought: the model.
          'ACEITE PARA MOTOR 1 LT 189.00': 'EN:ACEITE PARA MOTOR 1 LT 189.00',
          // The user's saved wording.
          'FORMA DE PAGO: EFECTIVO': 'Paid in cash',
          // Standard wording.
          'GRACIAS POR SU PREFERENCIA': 'Thank you for choosing us',
        },
      );
      expect(model.sent, ['ACEITE PARA MOTOR 1 LT 189.00']);

      TranslationEngine engineOf(String original) =>
          draft.lines.singleWhere((l) => l.originalText == original).engine;
      // Fixed translations are shown as such, so they are not learned again
      // as if the user had typed them.
      expect(engineOf('PRODUCTO: MAGNA'), TranslationEngine.glossary);
      expect(engineOf('TOTAL \$1,033.78'), TranslationEngine.glossary);
      expect(engineOf('GRACIAS POR SU PREFERENCIA'), TranslationEngine.glossary);
      expect(engineOf('FORMA DE PAGO: EFECTIVO'), TranslationEngine.glossary);
      expect(engineOf('ACEITE PARA MOTOR 1 LT 189.00'),
          TranslationEngine.onDevice);
      expect(engineOf('AV. INSURGENTES SUR 1234 COL. DEL VALLE'),
          TranslationEngine.manual);
    });
  });
}

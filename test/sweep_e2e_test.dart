import 'package:expense_assistant/domain/logic/item_line_parser.dart';
import 'package:expense_assistant/domain/logic/receipt_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Forty whole receipts, read end to end the way the app reads a photo:
/// the rows go through [ReceiptTextParser] for the shop, date, amount paid
/// and currency, and through [ItemLineParser] for the purchased items.
///
/// Every receipt is made up (generic names, numbers and tax IDs) but laid
/// out the way such a till, terminal or e-mail prints it, headers, tax lines
/// and footers included, with some of the damage OCR does. The expected
/// values are what a careful person would certainly read off the paper;
/// where two readings are defensible both are accepted or nothing is
/// asserted.
///
/// Results that were clearly wrong when the sweep was first run are not
/// asserted in the main group: each has its own small test in the "results
/// that were wrong" group. All of them are fixed.

// ---------------------------------------------------------------- Mexico

/// A sit-down restaurant's bill before paying: the tip is not included and
/// a table of suggested tips is printed under the total.
const _mxRestaurantBill = [
  'oO°',
  'LA CASA DEL EJEMPLO',
  'RESTAURANTE Y CANTINA',
  'OPERADORA GASTRONOMICA EJEMPLO SA DE CV',
  'RFC XXX010101AB1',
  'AV PASEO DE LA REFORMA 100 COL JUAREZ',
  'CUAUHTEMOC CDMX CP 06600',
  'TEL 55 0000 0000',
  'MESA 12  PERSONAS 2',
  'MESERO: CARLOS',
  'ORDEN 004512',
  '18/11/2026 14:35',
  'CANT DESCRIPCION IMPORTE',
  '2 SOPA DE TORTILLA 190.00',
  '1 ARRACHERA 300G 345.00',
  '1 ENCHILADAS SUIZAS 185.00',
  '2 CERVEZA MODELO ESP 130.00',
  '1 AGUA MINERAL 45.00',
  '1 FLAN NAPOLITANO 85.00',
  'SUBT0TAL 844.83',
  'IVA 16% 135.17',
  'TOTAL 980.00',
  'NOVECIENTOS OCHENTA PESOS 00/100 M.N.',
  'PROPINA SUGERIDA',
  '10% 98.00',
  '15% 147.00',
  '20% 196.00',
  'PROPINA NO INCLUIDA',
  'GRACIAS POR SU VISITA',
  'ESTE TICKET NO ES UN COMPROBANTE FISCAL',
  'FACTURACION EN LINEA: factura.ejemplo.mx',
];

/// The closed ticket of a restaurant paid by card, tip added on top.
const _mxRestaurantPaid = [
  'EL FOGON NORTENO',
  'SUC. POLANCO',
  'GRUPO FOGON EJEMPLO SA DE CV',
  'RFC: XXX010101AB1',
  'AV PRESIDENTE MASARYK 100 POLANCO',
  'CP 11560 MIGUEL HIDALGO CDMX',
  'LUGAR DE EXPEDICION: CIUDAD DE MEXICO',
  'FOLIO: 88213',
  'MESA: 7 PERS: 3',
  'MESERO: 14 JORGE',
  'FECHA: 20/11/2026 21:48:12',
  '------------------------------',
  'CANT. DESCRIPCION IMPORTE',
  '------------------------------',
  r'1 GUACAMOLE C/CHICHARRON $165.00',
  r'1 QUESO FUNDIDO $149.00',
  r'2 RIB EYE 400G $1,190.00',
  r'1 TACOS DE ARRACHERA $245.00',
  r'3 COPA VINO TINTO $495.00',
  r'2 CAFE ESPRESSO $90.00',
  r'1 PASTEL DE ELOTE $115.00',
  '------------------------------',
  r'SUB-TOTAL: $2,111.21',
  r'IVA: $337.79',
  r'TOTAL: $2,449.00',
  'PROPINA: S367.35',
  r'TOTAL PAGADO: $2, 816.35',
  'FORMA DE PAGO',
  r'TARJETA DE CREDITO $2,816.35',
  r'CAMBIO $0.00',
  'GRACIAS POR SU PREFERENCIA',
  'PARA FACTURAR INGRESE A',
  'www.ejemplo-facturacion.mx',
  'ESTE NO ES UN COMPROBANTE FISCAL',
];

/// A taqueria's order slip: the logo with the name was not read, so no
/// shop name is printed anywhere.
const _mxTaqueriaSlip = [
  'ORDEN: 0457',
  'MESA 4   PERSONAS 3',
  'MESERO: LUIS',
  '21/11/2026 22:17',
  '------------------------',
  'CANT PRODUCTO IMPORTE',
  '5 TACO PASTOR 110.00',
  '3 TACO SUADERO 66.00',
  '2 TACO BISTEC C/QUESO 64.00',
  '2 GRINGA PASTOR 130.00',
  '1 COSTRA DE QUESO 55.00',
  '1 ORDEN CEBOLLITAS 40.00',
  '1 GUACAMOLE CHICO 60.00',
  '2 AGUA HORCHATA 1L 70.00',
  '1 REFRESCO 30.00',
  '2 CERVEZA 90.00',
  '------------------------',
  r'TOTAL: $715.00',
  'PROPINA NO INCLUIDA',
  'GRACIAS POR SU PREFERENCIA',
  'ESTE NO ES UN COMPROBANTE FISCAL',
];

/// A coffee shop: the choices of each drink are printed under it, one of
/// them with its own price.
const _mxCafe = [
  'STARBUCKS COFFEE',
  'CAFE SIRENA S DE RL DE CV',
  'RFC XXX010101AB1',
  'SUC. REFORMA 222',
  'PASEO DE LA REFORMA 222 COL JUAREZ',
  'CIUDAD DE MEXICO CP 06600',
  'CHK 4521  19/11/2026 07:52',
  'CAJERO: ANA  TERMINAL 2',
  'PARA AQUI',
  '1 LATTE VENTI 89.00',
  'LECHE DE ALMENDRA 12.00',
  'SHOT EXTRA',
  '1 AMERICANO GRANDE 62.00',
  'SIN AZUCAR',
  '1 CROISSANT JAMON QUESO 79.00',
  'CALIENTE',
  '1 PANQUE DE LIMON 55.00',
  'SUBTOTAL 256.03',
  'IVA 16% 40.97',
  'TO TAL 297.00',
  'VISA 297.00',
  'XXXXXXXXXXXX1111',
  'AUT: 012345',
  'COMPRA CON CHIP',
  'GRACIAS POR TU VISITA',
  'FACTURA EN starbucks.ejemplo.mx',
  'TICKET: 0452119112026',
];

/// A fast-food kiosk ticket: the order number alone on a row, each combo
/// with its sides printed under it.
const _mxKiosk = [
  'BURGER KING',
  'OPERADORA DE HAMBURGUESAS EJEMPLO SA DE CV',
  'RFC XXX010101AB1',
  'BK PLAZA EJEMPLO 1234',
  'BLVD EJEMPLO 500 LOCAL FC-12',
  'GUADALAJARA JAL CP 44100',
  'KIOSKO 03',
  'SU ORDEN',
  '287',
  'PARA LLEVAR',
  '17/11/2026 13:26:41',
  '1 COMBO WHOPPER 159.00',
  'PAPAS MEDIANAS',
  'COCA COLA SIN AZUCAR MED',
  '1 COMBO KING DE POLLO 139.00',
  'AROS DE CEBOLLA',
  'SPRITE MED',
  '1 NUGGETS 10 PZ 85.00',
  '1 SUNDAE CHOCOLATE 35.00',
  'SUBTOTAL 360.34',
  'IVA 57.66',
  'TOTAL 418.00',
  'TARJETA DEBITO 418.00',
  '**** **** **** 1111',
  'APROBADA 012345',
  'CONSERVE SU TICKET',
  'CUENTANOS TU EXPERIENCIA',
  'www.ejemplo-encuesta.mx',
];

/// A bar tab paid in cash with the tip added; one drink has a number in
/// its name.
const _mxBar = [
  'CANTINA LA EJEMPLAR',
  'BAR & COCTELERIA',
  'CALLE REGINA 100 CENTRO HISTORICO',
  'CIUDAD DE MEXICO',
  'RFC XXX010101AB1',
  'CUENTA: 3318',
  'BARRA 2   PERSONAS: 4',
  'ATENDIO: MARIO',
  'FECHA: 20/11/2026',
  'ABIERTA 20:05  CERRADA 23:42',
  '4 CERVEZA VICTORIA 220.00',
  '3 CERVEZA INDIO 165.00',
  '2 MEZCAL ESPADIN 1.5OZ 280.00',
  '2 MARGARITA CLASICA 290.00',
  '1 GIN TONIC 175.00',
  '1 TEQUILA DON JULIO 70 240.00',
  '1 BOTANA MIXTA 185.00',
  '2 AGUA MINERAL 355ML 90.00',
  'SUBTOTAL 1,645.00',
  'PROPINA 10% 164.50',
  'TOTAL 1.809.50',
  'EFECTIVO 2,000.00',
  'CAMBIO 190.50',
  'SALUD! VUELVA PRONTO',
];

/// Breakfast at a hotel restaurant, charged to a card with the tip: the
/// hotel is named after its city and the outlet under it is just
/// "RESTAURANTE".
const _mxHotelRestaurant = [
  'HOTEL EJEMPLO CANCUN',
  'RESTAURANTE',
  'HOTELES EJEMPLO DE MEXICO SA DE CV',
  'RFC XXX010101AB1',
  'BLVD KUKULCAN KM 9.5 ZONA HOTELERA',
  'CHEQUE: 20415  MESA: 22',
  'HUESPEDES: 2  CAJERO: 105 SOFIA',
  '19 / 11 /2026 08:14 AM',
  '2 BUFFET DESAYUNO 790.00',
  '1 JUGO VERDE 85.00',
  '1 CAPUCHINO 75.00',
  'SUBTOTAL 818.97',
  'IVA 16% 131.03',
  'TOTAL 950.00',
  'PROPINA 142.50',
  'TOTAL CON PROPINA 1,092.50',
  'AMERICAN EXPRESS',
  'XXXXXXXXXXX1001',
  'AUTORIZACION 123456',
  'IMPORTE 1,092.50',
  'FIRMA: ______________________',
  'HABITACION: ________',
  'NOMBRE: ____________________',
  'GRACIAS POR SU PREFERENCIA',
];

/// A hotel folio: three nights with their taxes, two extras, settled by
/// card on departure, balance zero.
const _mxHotelFolio = [
  'HOTEL EJEMPLO CENTRO HISTORICO',
  'INMOBILIARIA HOTELERA EJEMPLO SA DE CV',
  'RFC XXX010101AB1',
  'AV JUAREZ 100 COL CENTRO CP 06010',
  'CIUDAD DE MEXICO',
  'ESTADO DE CUENTA / GUEST FOLIO',
  'HUESPED: CLIENTE EJEMPLO',
  'HABITACION: 814',
  'FOLIO: 100234',
  'LLEGADA: 16/11/2026',
  'SALIDA: 19/11/2026',
  'TARIFA: 2,150.00',
  'FECHA CONCEPTO CARGOS ABONOS',
  '16/11/26 HABITACION 2,150.00',
  '16/11/26 IVA 16% 344.00',
  '16/11/26 ISH 3.5% 75.25',
  '17/11/26 HABITACION 2,150.00',
  '17/11/26 IVA 16% 344.00',
  '17/11/26 ISH 3.5% 75.25',
  '17/11/26 RESTAURANTE 485.00',
  '18/11/26 HABITACION 2,150.00',
  '18/11/26 IVA 16% 344.00',
  '18/11/26 ISH 3.5% 75.25',
  '18/11/26 LAVANDERIA 260.00',
  '19/11/26 VISA XXXX1111 8,452.75',
  'TOTAL CARGOS 8,452.75',
  'TOTAL ABONOS 8,452.75',
  'SALDO 0.00',
  'GRACIAS POR SU ESTANCIA',
];

/// A convenience store, paid by card: the names were read as one block
/// and the prices as another; an O for the zero in the year and in TOTAL.
const _mxOxxo = [
  'OXXO',
  'CADENA COMERCIAL OXXO SA DE CV',
  'RFC: XXX010101AB1',
  'EDISON 1235 NTE COL TALLERES',
  'MONTERREY NL CP 64480',
  'REGIMEN GENERAL DE LEY PERSONAS MORALES',
  'TDA: 50ABC OXXO JUAREZ CENTRO',
  'AV JUAREZ 45 COL CENTRO',
  'CUAUHTEMOC CDMX CP 06010',
  'CAJA: 2  TICKET: 104522',
  'FECHA: 22/11/2O26 07:31',
  'CAJERO: 30412',
  '1 CAFE ANDATTI 16OZ',
  '1 SANDWICH JAMON',
  '2 AGUA CIEL 1L',
  '1 TRIDENT MENTA',
  '1 RECARGA TELCEL',
  '28.00',
  '49.00',
  '34.00',
  '18.50',
  '100.00',
  'T0TAL 229.50',
  'TARJETA BANCARIA 229.50',
  'ARTICULOS: 6',
  'IVA 16% 17.86',
  'IEPS 8% 0.00',
  'VISA DEBITO ************1111',
  'AUT 123456 AFIL 7654321',
  'ARQC: 0A1B2C3D4E5F6071',
  'FOLIO FACTURA: 0123456789012',
  'FACTURA EN www.ejemplo-factura.mx',
  'TIENES 30 DIAS PARA FACTURAR',
  'GRACIAS POR SU COMPRA',
];

/// Another convenience store: the name on one row and "quantity X price
/// total" on the next; time with PM.
const _mxSevenEleven = [
  '7-ELEVEN',
  '7-ELEVEN MEXICO SA DE CV',
  'RFC XXX010101AB1',
  'AV MUNICH 195-B COL CUAUHTEMOC',
  'SAN NICOLAS DE LOS GARZA NL',
  'TIENDA 1234 TECNOLOGICO',
  'AV EUGENIO GARZA SADA 2501',
  'MONTERREY NL',
  '18/11/2026 06:48:23 PM',
  'TICKET 004512 CAJA 01',
  'LE ATENDIO: EMPLEADO 2',
  'CAFE SELECT 20OZ',
  '1 X 32.00 32.00',
  'BIG BITE CLASICO',
  '2 X 29.00 58.00',
  'GATORADE NARANJA 600',
  '1 X 27.50 27.50',
  'CACAHUATE JAPONES 180G',
  '1 X 24.00 24.00',
  'SUBTOTAL 141.50',
  'TOTAL 141.50',
  'EFECTIVO 200.00',
  'CAMBIO 58.50',
  'TOTAL ARTICULOS 5',
  'IVA INCLUIDO 13.93',
  'GRACIAS POR SU COMPRA',
  'FACTURACION: www.ejemplo.mx',
];

/// A long supermarket ticket: the barcode after each name, a tax letter
/// after each price, goods sold by weight on two rows, and two discounts.
const _mxWalmart = [
  'WALMART',
  'NUEVA WAL MART DE MEXICO S DE RL DE CV',
  'NEXTENGO 78 SANTA CRUZ ACAYUCAN',
  'AZCAPOTZALCO CDMX CP 02770',
  'RFC XXX010101AB1',
  'UNIDAD BUENAVISTA',
  'TDA#2345 OP#00001234 TE#012 TR#04567',
  '21/11/26 18:42:07',
  'LECHE LALA ENTERA 1L 7501055300075 27.50 B',
  'PAN BIMBO BLANCO GDE 7501000111206 45.00 B',
  'HUEVO BLANCO 18 PZ 7501040090011 62.00 B',
  'PLATANO CHIAPAS 0000000040112',
  '0.845 KG X 24.90/KG 21.04 B',
  'JITOMATE SALADET 0000000040877',
  '1.210 KG X 32.00/KG 38.72 B',
  'PECHUGA POLLO S/H 2050000012345',
  '0.760 KG X 139.00/KG 105.64 B',
  'COCA COLA 2.5L 7501055310074',
  '2 X 42.00 84.00 A',
  'DETERGENTE ARIEL 3KG 7500435019811 149.00 A',
  'DESCUENTO ARIEL -30.00',
  'CAFE NESCAFE 225G 7501058617873 132.00 A',
  'AHORRO CAFE NESCAFE -12.00',
  'PAPEL HIG REGIO 12R 7501017372218 89.90 A',
  'SUBTOTAL 655.85',
  'IVA 56.95',
  'TOTAL 712.80',
  'EFECTIVO 800.00',
  'CAMBIO 87.20',
  'ARTICULOS VENDIDOS 11',
  'USTED AHORRO 42.00',
  'TC# 1234 5678 9012 3456 7890',
  'GRACIAS POR SU COMPRA',
  'FACTURA EN www.ejemplo-super.mx',
];

/// Another supermarket: the barcode before each name, the same tin three
/// times with a "3X2" promotion, cheese by weight, a "you saved" line.
const _mxChedraui = [
  'CHEDRAUI',
  'TIENDAS CHEDRAUI SA DE CV',
  'AV CONSTITUYENTES 1150 LOMAS ALTAS',
  'CDMX CP 11950 RFC XXX010101AB1',
  'SUC 123 CHEDRAUI SELECTO POLANCO',
  '22/11/2026 11:05 CAJA 14 TICKET 88102',
  'CAJERO(A): 4412',
  '7501031311309 SABRITAS ORIG 170G 54.00 T',
  '7501008042090 YOGHURT GRIEGO 900G 78.50',
  '7501003340115 ATUN DOLORES AGUA 140G 23.90',
  '7501003340115 ATUN DOLORES AGUA 140G 23.90',
  '7501003340115 ATUN DOLORES AGUA 140G 23.90',
  'PROMOCION 3X2 ATUN -23.90',
  '2000000456782 QUESO PANELA GRANEL',
  '0.385 kg x 189.00 72.77',
  '7502252480012 TORTILLA MAIZ 1KG 24.00',
  '7501055900015 CERVEZA CORONA 6PK 119.00 T',
  '7500478007509 SHAMPOO HS 375ML 92.00 T',
  'BOLSA REUTILIZABLE 15.00 T',
  'SUBTOTAL 503.07',
  'TOTAL 503.07',
  'TARJETA CREDITO 503.07',
  'AHORRO DE HOY 23.90',
  'IVA 16% 38.62',
  'IEPS 0.00',
  'NO. ARTICULOS: 10',
  'MONEDERO: PUNTOS GANADOS 5',
  'GRACIAS POR SU COMPRA',
];

/// A pharmacy: each name on its own row (dose and pack size in the name),
/// then "barcode quantity price amount"; a loyalty discount; cash.
const _mxPharmacy = [
  'FARMACIAS GUADALAJARA',
  'FARMACIA GUADALAJARA SA DE CV',
  'RFC XXX010101AB1',
  'ENRIQUE DIAZ DE LEON 261 COL VILLASENOR',
  'GUADALAJARA JAL CP 44600',
  'SUC 1045 CHAPULTEPEC',
  'AV CHAPULTEPEC 120 COL AMERICANA',
  'TICKET: 0045123  CAJA: 3',
  'FECHA: 16/11/2026  HORA: 19:22',
  'VENDEDOR: 20418',
  'ARTICULO CANT PRECIO IMPORTE',
  'PARACETAMOL 500MG 20 TAB',
  '7501234567890 1 38.50 38.50',
  'IBUPROFENO 400MG 10 CAP',
  '7501234567906 2 45.00 90.00',
  'SUERO ELECTROLIT COCO 625',
  '7501234567913 3 24.00 72.00',
  'CURITAS C/20',
  '7501234567920 1 32.00 32.00',
  'PROTECTOR SOLAR FPS50 120ML',
  '7501234567937 1 289.00 289.00',
  'DESCUENTO MONEDERO -28.90',
  'SUBTOTAL 492.60',
  'IVA 40.29',
  r'TOTAL A PAGAR $ 492.60',
  r'EFECTIVO $ 500.00',
  r'SU CAMBIO $ 7.40',
  'ARTICULOS: 8',
  'SON: CUATROCIENTOS NOVENTA Y DOS PESOS 60/100 M.N.',
  r'USTED AHORRO: $28.90',
  'GRACIAS POR SU COMPRA',
];

/// A fuel station ticket where every figure follows its label; the date
/// is printed year first.
const _mxPemex = [
  'GASOLINERA EJEMPLO SA DE CV',
  'ESTACION DE SERVICIO 12345',
  'PEMEX',
  'RFC: XXX010101AB1',
  'CARR MEXICO-TOLUCA KM 45.5',
  'LERMA EDO DE MEXICO CP 52000',
  'PERMISO CRE: PL/00000/EXP/ES/2015',
  'TICKET DE VENTA',
  'FOLIO: 778123',
  'FECHA: 2026-11-21 16:08:55',
  'BOMBA: 04  MANGUERA: 2',
  'DESPACHADOR: 17',
  'PRODUCTO: MAGNA 87 OCT',
  'CANTIDAD: 38.462 LTS',
  r'PRECIO UNITARIO: $23.89',
  r'IMPORTE: $918.86',
  r'SUBTOTAL: $801.38',
  r'IVA: $117.48',
  'TOTAL: 5918.86',
  'NOVECIENTOS DIECIOCHO PESOS 86/100 M.N.',
  'FORMA DE PAGO: TARJETA DE DEBITO',
  'TARJETA: ************1111',
  'AUTORIZACION: 123456',
  'ODOMETRO: 45210',
  'PLACAS: ABC1234',
  'FACTURE EN: www.ejemplo-gas.mx',
  'WEB ID: 1A2B3C4D',
  'GRACIAS POR SU PREFERENCIA',
];

/// Another fuel station, laid out as a table: litres of fuel and a bottle
/// of oil, paid in cash.
const _mxFuelTable = [
  'MOBIL',
  'SERVICIO EJEMPLO DEL BAJIO SA DE CV',
  'E.S. 9876',
  'BLVD ADOLFO LOPEZ MATEOS 1500',
  'LEON GTO CP 37000',
  'RFC XXX010101AB1',
  'NOTA DE VENTA 0098812',
  '20/11/2026 09:14',
  'ISLA 3 BOMBA 6',
  'DESPACHADOR: 08',
  'CANT. DESCRIPCION P.U. IMPORTE',
  '30.120 L PREMIUM 25.99 782.82',
  '1 ACEITE MOBIL SUPER 1L 189.00 189.00',
  'SUBTOTAL 837.78',
  'IVA 134.04',
  'TOTAL S971.82',
  r'EFECTIVO $1,000.00',
  r'CAMBIO $28.18',
  'NOVECIENTOS SETENTA Y UN PESOS 82/100 M.N.',
  'PERMISO CRE PL/00000/EXP/ES/2016',
  'FACTURACION: www.ejemplo-combustible.mx',
  'GRACIAS POR SU PREFERENCIA',
];

/// A motorway toll booth.
const _mxToll = [
  'CAPUFE',
  'CAMINOS Y PUENTES FEDERALES',
  'DE INGRESOS Y SERVICIOS CONEXOS',
  'RFC XXX010101AB1',
  'PLAZA DE COBRO 027 TEPOTZOTLAN',
  'AUTOPISTA MEXICO - QUERETARO',
  'CARRIL: 07  TURNO: 2',
  'CAJERO: 30125',
  'FOLIO: 0457812',
  'FECHA: 17/11/2026',
  'HORA: 06:42:18',
  'CLASE: AUTOMOVIL (A)',
  'EJES: 2',
  'FORMA DE PAGO: EFECTIVO',
  r'IMPORTE: $ 104.00',
  'IVA INCLUIDO',
  'CONSERVE ESTE COMPROBANTE',
  'ES SU SEGURO DE USUARIO',
  'FACTURACION: www.ejemplo-peaje.mx',
  'BUEN VIAJE',
];

/// A car park's pay-station receipt: time in, time out, the hourly rate,
/// the total, cash given and change.
const _mxParking = [
  'ESTACIONAMIENTOS EJEMPLO',
  'OPERADORA DE ESTACIONAMIENTOS EJEMPLO SA DE CV',
  'RFC XXX010101AB1',
  'PLAZA SATELITE NIVEL S1',
  'CTO CENTRO COMERCIAL 2251 NAUCALPAN',
  'COMPROBANTE DE PAGO',
  'CAJERO AUTOMATICO 03',
  'BOLETO: 0012345678',
  'ENTRADA: 19/11/2026 10:12',
  'SALIDA: 19/11/2026 13:47',
  'TIEMPO: 03:35',
  r'TARIFA: $20.00 POR HORA O FRACCION',
  'TOTAL:',
  'RECIBIDO:',
  'CAMBIO:',
  r'$80.00',
  r'$100.00',
  r'$20.00',
  'IVA INCLUIDO',
  'TIENE 15 MIN PARA SALIR',
  'NO NOS HACEMOS RESPONSABLES POR OBJETOS',
  'OLVIDADOS EN SU VEHICULO',
  'FACTURA: www.ejemplo-parking.mx',
];

/// A duty-free shop: priced and paid in US dollars, the total repeated in
/// pesos with the exchange rate.
const _mxAirportShop = [
  'DUFRY',
  'DUFRY MEXICO SA DE CV',
  'RFC XXX010101AB1',
  'AEROPUERTO INTERNACIONAL DE CANCUN',
  'TERMINAL 3 SALIDAS INTERNACIONALES',
  'TICKET 0045871  CAJA 05',
  '22/11/2026 15:20',
  'VENDEDOR 1042',
  'VUELO AM0456  DESTINO GUA',
  'PASE DE ABORDAR VERIFICADO',
  'PRECIOS EN USD',
  '1 TEQUILA REPOSADO 750ML 62.00',
  '2 CHOCOLATE TOBLERONE 360G 28.00',
  '1 PERFUME EDT 50ML 79.00',
  'SUBTOTAL USD 169.00',
  'TOTAL USD 169.00',
  'TOTAL MXN 3,143.40',
  'TIPO DE CAMBIO 18.60',
  'PAGO TARJETA USD 169.00',
  'VISA ************1111',
  'AUT 123456',
  'DUTY FREE - LIBRE DE IMPUESTOS',
  'MERCANCIA PARA EXPORTACION',
  'NO SE ACEPTAN DEVOLUCIONES SIN TICKET',
  'GRACIAS POR SU COMPRA',
];

/// A card terminal's slip on its own: the bank on top, then the shop; each
/// label on one row and its figure on the next, the peso sign read as "S".
const _mxCardSlip = [
  'BBVA',
  'RESTAURANTE EL EJEMPLO',
  'AV REVOLUCION 100 SAN ANGEL',
  'CIUDAD DE MEXICO',
  'AFILIACION: 1234567',
  'TERMINAL: 00012345',
  'VENTA',
  'VISA CREDITO',
  '************1111',
  'FECHA: 21/11/26 HORA: 15:02',
  'AUT: 012345  REF: 000123456789',
  'ARQC: 1A2B3C4D5E6F7081',
  'AID: A0000000031010',
  'IMPORTE',
  'S 850.00',
  'PROPINA',
  'S 127.50',
  'TOTAL',
  r'$ 977.50',
  'FIRMA ELECTRONICA / PIN VERIFICADO',
  'PAGARE NEGOCIABLE UNICAMENTE CON',
  'INSTITUCIONES DE CREDITO',
  'COPIA CLIENTE',
];

/// A ride receipt as the e-mail shows it, amounts written "MX$".
const _mxUber = [
  'Uber',
  r'Total MX$187.43',
  '22 de noviembre de 2026',
  'Gracias por viajar, Cliente',
  'Esperamos que hayas disfrutado tu viaje de esta tarde.',
  'Total',
  r'MX$187.43',
  r'Tarifa del viaje MX$152.10',
  r'Subtotal MX$152.10',
  r'Cuota de solicitud MX$14.25',
  r'Tarifa de aeropuerto MX$21.08',
  'Pagos',
  'Visa ••••1111',
  '22/11/26 17:45',
  r'MX$187.43',
  'Viajaste con Conductor',
  'UberX 12.4 kilometros | 28 min',
  '17:12 | Av. Ejemplo 100, Col. Centro, Ciudad de Mexico',
  '17:40 | Aeropuerto Internacional, Terminal 2, Ciudad de Mexico',
  'Es posible que el importe incluya impuestos.',
];

/// Another ride e-mail: the total on its own row, the date written
/// "20 nov 2026", the fare broken down.
const _mxDidi = [
  'DiDi',
  'Recibo de viaje',
  'Hola Cliente, gracias por viajar con DiDi',
  'Total pagado',
  r'$96.50',
  'MXN',
  '20 nov 2026, 08:14',
  'DiDi Express',
  'Origen: Calle Ejemplo 12, Roma Norte',
  'Destino: Av. Ejemplo 500, Santa Fe',
  'Distancia 9.8 km  Duracion 31 min',
  'Detalles de la tarifa',
  r'Tarifa base $18.00',
  r'Distancia $49.00',
  r'Tiempo $24.50',
  r'Cuota de servicio $5.00',
  r'Total $96.50',
  'Metodo de pago',
  r'Tarjeta ****1111 $96.50',
  'DiDi Mobility Mexico SA de CV',
  'RFC XXX010101AB1',
  'Este recibo no es una factura fiscal.',
];

/// An airline's receipt for an extra bag, paid at the airport: issued the
/// day before, the flight two days later; dates written "22NOV26".
const _mxBaggage = [
  'AEROMEXICO',
  'AEROVIAS DE MEXICO SA DE CV',
  'RFC XXX010101AB1',
  'AEROPUERTO INTL BENITO JUAREZ T2',
  'RECIBO DE CARGOS VARIOS / EMD',
  'DOCUMENTO: 139 4512345678',
  'PASAJERO: CLIENTE/EJEMPLO MR',
  'CLAVE DE RESERVACION: ABCDEF',
  'VUELO: AM 678  MEX-GUA',
  'FECHA DE VUELO: 24NOV26',
  'FECHA DE EMISION: 22NOV26',
  'CONCEPTO: EXCESO DE EQUIPAJE',
  '1 MALETA ADICIONAL 23KG',
  'TARIFA MXN 1,200.00',
  'IVA MXN 192.00',
  'TOTAL MXN 1,392.00',
  'FORMA DE PAGO: CC VI XXXXXXXXXXXX1111',
  'AUTORIZACION: 123456',
  'AGENTE: 4512 MEXTO',
  'NO REEMBOLSABLE',
  'GRACIAS POR VOLAR CON AEROMEXICO',
];

/// A coach ticket bought two days before travelling.
const _mxBus = [
  'ADO',
  'AUTOBUSES DE ORIENTE ADO SA DE CV',
  'RFC XXX010101AB1',
  'BOLETO DE VIAJE',
  'ORIGEN: MEXICO TAPO',
  'DESTINO: PUEBLA CAPU',
  'FECHA DE VIAJE: 23/11/2026',
  'HORA DE SALIDA: 14:30',
  'ASIENTO: 12  SERVICIO: ADO GL',
  'PASAJERO: CLIENTE EJEMPLO',
  'TIPO: ADULTO',
  'FOLIO: 1234567890',
  r'TARIFA: $ 318.97',
  r'IVA: $ 51.03',
  r'TOTAL: $ 370.00',
  'FORMA DE PAGO: TARJETA',
  'FECHA DE COMPRA: 21/11/2026 10:02',
  'TAQUILLA 08 CAJERO 4412',
  'SEGURO DE VIAJERO INCLUIDO',
  'PRESENTARSE 30 MIN ANTES DE LA SALIDA',
  'www.ejemplo-bus.mx',
];

// ------------------------------------------------------------- Guatemala

/// A cafe's electronic invoice (FEL): the trade name above the company,
/// the buyer as "CF", unit price and total per line, tax included.
const _gtCafe = [
  'CAFE EJEMPLO ANTIGUA',
  'INVERSIONES CAFETALERAS EJEMPLO, SOCIEDAD ANONIMA',
  'NIT: 1234567-8',
  '5A AVENIDA NORTE 12, ANTIGUA GUATEMALA',
  'SACATEPEQUEZ',
  'FACTURA',
  'DOCUMENTO TRIBUTARIO ELECTRONICO',
  'SERIE: 1A2B3C4D  NUMERO: 1234567890',
  'NUMERO DE AUTORIZACION:',
  '1A2B3C4D-5E6F-7081-92A3-B4C5D6E7F809',
  'FECHA DE EMISION:',
  '21/11/2026 09:15:22',
  'NIT: CF',
  'NOMBRE: CONSUMIDOR FINAL',
  'CANT DESCRIPCION P/U TOTAL',
  '2 CAPUCHINO 22.00 44.00',
  '1 CAFE AMERICANO 16.00 16.00',
  '1 PASTEL DE ZANAHORIA 28.00 28.00',
  '1 SANDWICH DE POLLO 42.00 42.00',
  'TOTAL Q 130.OO',
  'CIENTO TREINTA QUETZALES EXACTOS',
  'IVA INCLUIDO Q 13.93',
  'EFECTIVO Q 150.00',
  'CAMBIO Q 20.00',
  'SUJETO A PAGOS TRIMESTRALES ISR',
  'CERTIFICADOR: EJEMPLO FEL, S.A. NIT: 9876543-2',
  'GRACIAS POR SU VISITA',
];

/// A restaurant's FEL invoice with the 10% tip added and paid by card.
const _gtRestaurant = [
  'RESTAURANTE EL EJEMPLO CHAPIN',
  'COMIDA TIPICA GUATEMALTECA',
  'ALIMENTOS EJEMPLO, S.A.',
  'NIT 123456-7',
  '6A CALLE 7-21 ZONA 10, GUATEMALA',
  'TEL: 2000-0000',
  'FACTURA ELECTRONICA FEL',
  'SERIE ABCD1234 No. 987654321',
  'AUTORIZACION',
  'ABCD1234-0000-1111-2222-333344445555',
  'FECHA: 20/11/2026 HORA: 20:31',
  'MESA: 14 MESERO: PEDRO',
  'NIT CLIENTE: CF',
  'NOMBRE: CONSUMIDOR FINAL',
  'CANT. DESCRIPCION TOTAL',
  '1 PEPIAN DE POLLO Q78.00',
  '1 KAK IK Q85.00',
  '1 GUACAMOL CON TOTOPOS Q42.00',
  '2 CERVEZA GALLO Q50.00',
  '1 LIMONADA CON SODA Q22.00',
  '1 RELLENITOS DE PLATANO Q30.00',
  'SUBTOTAL Q307.00',
  'PROPINA 10% Q30.70',
  'TOTAL A PAGAR',
  'Q337.70',
  'TARJETA VISA ****1111 Q337.70',
  'IVA (12%) INCLUIDO Q32.89',
  'TRESCIENTOS TREINTA Y SIETE QUETZALES CON 70/100',
  'LA PROPINA ES VOLUNTARIA',
  'CERTIFICADOR: EJEMPLO, S.A. NIT 1111111-1',
  'SUJETO A RETENCION DEFINITIVA ISR',
];

/// A fuel station's FEL invoice: gallons, price and total on one row, the
/// fuel tax (IDP) listed, change called "VUELTO".
const _gtFuel = [
  'ESTACION DE SERVICIO EJEMPLO',
  'PUMA ENERGY',
  'GASOLINERAS EJEMPLO, S.A.',
  'NIT: 765432-1',
  'KM 18.5 CARRETERA A EL SALVADOR',
  'SANTA CATARINA PINULA, GUATEMALA',
  'FACTURA ELECTRONICA',
  'SERIE: F1A2B3C4  DTE: 2468013579',
  'FECHA: 22/11/2026 07:48',
  'NIT: 1234567K',
  'NOMBRE: EMPRESA EJEMPLO, S.A.',
  'BOMBA 03  MANGUERA 1',
  'PRODUCTO GALONES PRECIO TOTAL',
  'SUPER 8.524 31.49 268.42',
  'IDP Q 40.06',
  'TOTAL Q 268.42',
  'EFECTIVO Q 300.00',
  'VUELTO Q 31.58',
  'IVA INCLUIDO',
  'PILOTO: ____________',
  'PLACA: P123ABC',
  'CERTIFICADOR: EJEMPLO, S.A.',
  'GRACIAS POR SU COMPRA',
];

/// A supermarket's FEL invoice: barcode and name on one row, "quantity UN
/// X price total" on the next, tomatoes by the pound, a club discount.
const _gtSupermarket = [
  'SUPERMERCADOS LA TORRE',
  'UNISUPER, S.A.',
  'NIT: 2222222-2',
  'CALZADA ROOSEVELT 25-50 ZONA 7',
  'GUATEMALA, GUATEMALA',
  'FACTURA ELECTRONICA EN LINEA FEL',
  'SERIE: 5F6E7D8C NUMERO: 135792468',
  'FECHA EMISION: 19/11/2026 18:05:44',
  'CAJA: 06 CAJERO: 1234',
  'NIT: CF NOMBRE: CONSUMIDOR FINAL',
  '7401005912345 AGUA PURA SALVAVIDAS 600ML',
  '3 UN X 4.50 13.50',
  '7401001234567 FRIJOL NEGRO DUCAL 400G',
  '2 UN X 9.75 19.50',
  '7402000345678 PAN SANDWICH BIMBO',
  '1 UN X 21.95 21.95',
  '2000004500000 TOMATE MANZANO',
  '1.250 LB X 5.60 7.00',
  '7411000123456 CAFE LEON MOLIDO 350G',
  '1 UN X 38.90 38.90',
  '7406171012345 TORTRIX LIMON 180G',
  '1 UN X 12.25 12.25',
  'DESCUENTO CLUB -3.89',
  'SUB-TOTAL 109.21',
  'TOTAL Q. 109.21',
  'TARJETA DE DEBITO Q. 109.21',
  'ARTICULOS: 9',
  'IVA 12% INCLUIDO: 11.70',
  'AHORRO TOTAL: Q. 3.89',
  'CERTIFICADOR: EJEMPLO, S.A. NIT: 3333333-3',
  'GRACIAS POR PREFERIRNOS',
];

/// A fried-chicken counter's FEL invoice: numbers inside the names, sides
/// under the menu, paid in cash with change.
const _gtFastFood = [
  'POLLO CAMPERO',
  'POLLO CAMPERO, S.A.',
  'NIT: 444444-4',
  'CAMPERO AEROPUERTO LA AURORA',
  '9A AVENIDA 14-75 ZONA 13 GUATEMALA',
  'FACTURA FEL',
  'SERIE 9Z8Y7X6W NO 1122334455',
  'AUTORIZACION: 9Z8Y7X6W-1111-2222-3333-444455556666',
  '22/11/2026 12:41 PM',
  'ORDEN 152 PARA LLEVAR',
  'CAJERO: MARIA',
  'NIT: CF',
  '1 MENU CAMPERO 3 PIEZAS 62.00',
  'PAPAS FRITAS',
  'GASEOSA PEPSI 16OZ',
  '1 CAMPERITOS 6 UN 39.00',
  '1 ENSALADA COLESLAW 14.00',
  '1 PIE DE QUESO 18.00',
  'SUBTOTAL 118.75',
  'IVA 12% 14.25',
  'TOTAL Q133.00',
  'EFECTIVO Q200.00',
  'SU VUELTO Q67.00',
  'CERTIFICADOR: EJEMPLO, S.A. NIT: 5555555-5',
  'GRACIAS POR SU COMPRA',
];

// ----------------------------------------------------------- El Salvador

/// A pupuseria's electronic invoice (DTE) in US dollars, 10% tip added.
const _svRestaurant = [
  'PUPUSERIA LA EJEMPLAR',
  'INVERSIONES EJEMPLO, S.A. DE C.V.',
  'NIT: 0614-010101-101-1',
  'NRC: 123456-7',
  'GIRO: RESTAURANTES',
  'BLVD DEL HIPODROMO 100, SAN SALVADOR',
  'DOCUMENTO TRIBUTARIO ELECTRONICO',
  'FACTURA',
  'CODIGO DE GENERACION:',
  'A1B2C3D4-E5F6-7081-92A3-B4C5D6E7F809',
  'NUMERO DE CONTROL:',
  'DTE-01-M001P001-000000000012345',
  'SELLO DE RECEPCION: 2026ABCDEF0123456789',
  'FECHA Y HORA: 18/11/202612:55:10',
  'CLIENTE: CONSUMIDOR FINAL',
  'CANT DESCRIPCION P.UNIT TOTAL',
  '4 PUPUSA REVUELTA 1.25 5.00',
  '2 PUPUSA QUESO LOROCO 1.50 3.00',
  '1 YUCA FRITA CON CHICHARRON 4.75 4.75',
  '2 HORCHATA 1.75 3.50',
  '1 CAFE 1.25 1.25',
  r'SUMAS $17.50',
  r'VENTAS GRAVADAS $17.50',
  r'SUBTOTAL $17.50',
  r'PROPINA 10% $1.75',
  'TOTAL A PAGAR S19.25',
  'DIECINUEVE 25/100 DOLARES',
  r'EFECTIVO $20.00',
  r'CAMBIO $0.75',
  'IVA INCLUIDO',
  'GRACIAS POR SU VISITA',
];

/// A supermarket's DTE: a tax letter after each price, cheese by the
/// pound, change called "VUELTO".
const _svSupermarket = [
  'SUPER SELECTOS',
  'CALLEJA, S.A. DE C.V.',
  'NIT 0614-020202-102-2 NRC 12345-6',
  'SUCURSAL ESCALON',
  'PASEO GENERAL ESCALON, SAN SALVADOR',
  'FACTURA DE CONSUMIDOR FINAL',
  'DTE-01-S012P003-000000000098765',
  'COD. GENERACION',
  '0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0',
  'FECHA: 17/11/2026 HORA: 17:20',
  'CAJA 3 CAJERO 8841',
  'AGUA CRISTAL 1.5L 1.15 G',
  'PAN DE CAJA BIMBO 2.85 G',
  'QUESO DURO BLANDO LB',
  '0.75 LB X 4.60 3.45 G',
  'CAFE LISTO 50G 2.10 G',
  'JUGO DEL VALLE NARANJA 1L 1.95 G',
  'PROTECTOR SOLAR 120ML 9.75 G',
  'SUBTOTAL 21.25',
  r'TOTAL $ 21.25',
  r'EFECTIVO $ 25.00',
  r'VUELTO $ 3.75',
  'G = GRAVADO  E = EXENTO',
  'ARTICULOS 6',
  'IVA 13% INCLUIDO 2.44',
  'GRACIAS POR SU COMPRA',
];

// ------------------------------------------------------------- Venezuela

/// A fiscal printer's invoice in bolivars: "2 x Bs 520,00" above the name
/// when more than one, tax added under the subtotal, IGTF for paying in
/// foreign currency, and the total repeated in dollars for reference.
const _veRestaurant = [
  'SENIAT',
  'RIF: J-00000000-0',
  'RESTAURANT EL EJEMPLO, C.A.',
  'AV FRANCISCO DE MIRANDA, CHACAO',
  'CARACAS, EDO. MIRANDA',
  'RIF/C.I.: V-00000000',
  'RAZON SOCIAL: CLIENTE EJEMPLO',
  'FACTURA',
  'FACTURA: 00012345',
  'FECHA: 19-11-2026 HORA: 13:42',
  '2 x Bs 520,00',
  'AREPA REINA PEPIADA (G) Bs 1.040,00',
  'PABELLON CRIOLLO (G) Bs 1.450,00',
  '2 x Bs 180,00',
  'JUGO DE PARCHITA (G) Bs 360,00',
  'CAFE MARRON (G) Bs 240,00',
  'SUBTTL Bs 3.090,00',
  'BI G (16,00%) Bs 3.090,00',
  'IVA G (16,00%) Bs 494,40',
  'IGTF (3,00%) Bs 107,53',
  'TOTAL Bs 3.691,93',
  'DIVISAS Bs 3.691,93',
  'TASA BCV: 145,00',
  'REF USD 25,46',
  'MH Z1A1234567',
];

/// A pharmacy's fiscal invoice in bolivars, one item exempt, paid by debit
/// card, the total repeated in dollars.
const _vePharmacy = [
  'FARMATODO, C.A.',
  'RIF J-00000000-1',
  'AV. LIBERTADOR, EDIF. EJEMPLO, CARACAS',
  'TIENDA 045 LAS MERCEDES',
  'CLIENTE: CLIENTE EJEMPLO',
  'RIF/C.I.: V00000000',
  'FACTURA 00098765',
  'FECHA: 21/11/2026 HORA: 10:15 AM',
  'CAJA: 02 CAJERO: 0045',
  'ACETAMINOFEN 500MG X10 (E) Bs 285,00',
  'PROTECTOR SOLAR FPS50 (G) Bs 2.150,00',
  'AGUA MINERAL 600ML (G) Bs 95,50',
  'PANUELOS FACIALES X3 (G) Bs 310,00',
  'SUBTTL Bs 2.840,50',
  'EXENTO (E) Bs 285,00',
  'BI G (16,00%) Bs 2.555,50',
  'IVA G (16,00%) Bs 408,88',
  'TOTAL Bs 3.249,38',
  'T. DEBITO Bs 3.249,38',
  r'TOTAL REF. $ 22,41',
  'TASA BCV Bs 145,00',
  'MH Z1B7654321',
  'GRACIAS POR SU COMPRA',
];

// -------------------------------------------------------------- Colombia

/// A restaurant's electronic POS invoice in pesos: a dot for thousands, no
/// decimals, consumption tax, a voluntary tip, and the tax office's
/// resolution with its own date in the footer.
const _coRestaurant = [
  'RESTAURANTE EL EJEMPLO PAISA',
  'INVERSIONES GASTRONOMICAS EJEMPLO SAS',
  'NIT 900.000.000-1',
  'CRA 13 # 85-20 BOGOTA D.C.',
  'TEL 601 0000000',
  'RESPONSABLE DE IMPOCONSUMO',
  'FACTURA ELECTRONICA DE VENTA',
  'No. FEPV 45123',
  'FECHA: 18/11/2026 HORA: 13:20',
  'MESA: 8 MESERO: ANDRES',
  'CLIENTE: CONSUMIDOR FINAL',
  'CC/NIT: 222222222222',
  'CANT DESCRIPCION VALOR',
  r'1 BANDEJA PAISA $ 42.000',
  r'1 AJIACO SANTAFERENO $ 36.000',
  r'2 LIMONADA DE COCO $ 24.000',
  r'1 CERVEZA CLUB COLOMBIA $ 9.500',
  r'1 POSTRE TRES LECHES $ 14.000',
  r'SUBTOTAL $ 116.204',
  r'IMPOCONSUMO 8% $ 9.296',
  r'TOTAL $ 125.500',
  r'PROPINA VOLUNTARIA 10% $ 11.620',
  'TOTAL A PAGAR S 137.120',
  r'TARJETA CREDITO $ 137.120',
  'CUFE: 0a1b2c3d4e5f60718293a4b5c6d7e8f9',
  'RESOLUCION DIAN 18764000000000 DE 2025-01-15',
  'PREFIJO FEPV DEL 1 AL 100000',
  'GRACIAS POR SU VISITA',
];

/// A supermarket's POS invoice in pesos: a line number and a barcode
/// before each name, bananas by weight with a comma, the date year first.
const _coSupermarket = [
  'EXITO',
  'ALMACENES EXITO S.A.',
  'NIT 800.000.000-2',
  'EXITO CALLE 80',
  'AV CALLE 80 # 69Q-50 BOGOTA',
  'FACTURA ELECTRONICA DE VENTA POS',
  'NRO: P123 456789',
  'FECHA: 2026/11/20 HORA: 18:32:10',
  'CAJA: 012 CAJERO: 3456',
  'PLU DETALLE PRECIO',
  '1 7702001012345 AGUA CRISTAL 600ML 2.300',
  '2 7702004098765 PAN TAJADO BIMBO 7.950 A',
  '3 7701234500012 CAFE SELLO ROJO 500G 21.900',
  '4 7707654300019 JABON PROTEX X3 9.800 A',
  '5 2000001234567 BANANO',
  '0,850 KG X 2.400 2.040',
  '6 7702129012345 CHOCOLATINA JET 12U 13.500 A',
  'DCTO PROMO JET -2.700',
  'SUBTOTAL 54.790',
  'TOTAL A PAGAR 54.790',
  'EFECTIVO 60.000',
  'CAMBIO 5.210',
  'IVA 19% 4.558',
  'TOTAL ARTICULOS 6',
  'PUNTOS COLOMBIA ACUMULADOS 54',
  'RESOLUCION DIAN No 18764012345678',
  'FECHA 2025/03/10 DEL P123 1 AL 999999',
  'GRACIAS POR SU COMPRA',
];

// --------------------------------------------------------- United States

/// A diner's card slip: tax under the subtotal, the tip and total lines
/// left blank to be filled in by hand, suggested gratuities, month first.
const _usDiner = [
  'EXAMPLE STREET DINER',
  '123 MAIN STREET',
  'AUSTIN, TX 78701',
  '(512) 555-0100',
  'Server: Jenny   Station: 4',
  'Order #: 2218   Table 12   Guests: 2',
  '11/19/2026 8:42 AM',
  'Dine In',
  '2 Coffee 7.00',
  '1 Pancake Stack 11.50',
  '1 Denver Omelette 13.95',
  'Add Avocado 2.00',
  'Wheat Toast',
  '1 Side Bacon 4.50',
  '1 Orange Juice Lg 4.75',
  'Subtotal 43.70',
  'Tax 3.61',
  'Total 47.31',
  'Visa xxxxxxxxxxxx1111',
  'Auth: 01234A',
  'Amount: S47.31',
  'Tip: ____________',
  'Total: ____________',
  'X_________________________',
  'Suggested Gratuity',
  r'18% $7.87',
  r'20% $8.74',
  r'22% $9.61',
  'Thank you for dining with us!',
  'Customer Copy',
];

/// A US drugstore: a tax letter stuck to each price, "2 @ 2.29", a coupon,
/// the date in words near the bottom and a later "returns until" date.
const _usDrugstore = [
  'CVS pharmacy',
  '1500 EXAMPLE AVE',
  'NEW YORK, NY 10001',
  '(212) 555-0142',
  'REG#04 TRN#5512 CSHR#0098765 STR#1234',
  'ExtraCare Card #: *********1234',
  '1 ADVIL TABS 200MG 24CT 8.49T',
  '1 CVS HAND SANITIZER 2OZ 2.79T',
  '2 POLAND SPRING WTR 1L',
  '2 @ 2.29 4.58B',
  '1 TRAVEL TOOTHBRUSH KIT 4.99T',
  'COUPON ADVIL -2.00',
  '5 ITEMS',
  'SUBTOTAL 18.85',
  'NY 8.875% TAX 1.27',
  'TOTAL 20.12',
  'CHARGE 20.12',
  'MASTERCARD ************1111',
  'APPROVED# 012345',
  'REF# 123456',
  'ENTRY METHOD: CHIP READ',
  'CHANGE .00',
  'NOVEMBER 20, 2026 3:17 PM',
  'RETURNS WITH RECEIPT THRU 01/19/2027',
  'THANK YOU. SHOP 24 HOURS AT CVS.COM',
];

/// A US pay-at-the-pump receipt: gallons, a price per gallon with three
/// decimals, the date month first with a day that could pass for a month.
const _usFuel = [
  'SHELL',
  'EXAMPLE FUEL MART #1234',
  '4500 AIRPORT BLVD',
  'HOUSTON TX 77032',
  '11/08/26 06:12',
  'INVOICE# 045812',
  'TRAN# 9012345',
  'PUMP# 07',
  'REGULAR UNLEADED',
  'GALLONS 11.482',
  r'PRICE/GAL $2.899',
  r'FUEL TOTAL $33.29',
  r'CREDIT $33.29',
  'VISA XXXXXXXXXXXX1111',
  'AUTH# 01234B',
  'ENTRY: CONTACTLESS',
  'AID: A0000000031010',
  'SITE ID: 0000123456',
  'THANK YOU',
  'HAVE A NICE DAY',
];

// -------------------------------------------------------- United Kingdom

/// A pub's bill with an optional service charge added, paid by card, the
/// VAT breakdown under the payment; one pound sign read as "E".
const _ukPub = [
  'THE EXAMPLE ARMS',
  '12 HIGH STREET',
  'LONDON SW1A 1AA',
  'TEL: 020 7946 0000',
  'VAT NO: GB 000 0000 00',
  'TABLE 14   COVERS 3',
  'SERVER: TOM',
  'CHECK 004512',
  '18/11/2026 19:42',
  '2 PINT LONDON PRIDE 12.40',
  '1 175ML SAUVIGNON BLANC 7.95',
  '1 FISH & CHIPS 16.50',
  '1 STEAK & ALE PIE 15.95',
  '1 HALLOUMI BURGER 14.50',
  '1 STICKY TOFFEE PUDDING 7.50',
  '1 DIET COKE 3.60',
  'SUBTOTAL 78.40',
  'SERVICE CHARGE 12.5% 9.80',
  'TOTAL DUE £88.20',
  'VISA DEBIT E88.20',
  '************1111',
  'AUTH CODE: 012345',
  'CONTACTLESS',
  'VAT @ 20% 13.07',
  'NET 65.33',
  'AN OPTIONAL SERVICE CHARGE OF 12.5%',
  'HAS BEEN ADDED TO YOUR BILL',
  'THANK YOU FOR YOUR VISIT',
];

/// A UK sandwich shop: a choice under the porridge, and a VAT table whose
/// row holds the rate, net, tax and gross.
const _ukCafe = [
  'PRET A MANGER',
  'SHOP 245 KINGS CROSS STATION',
  'LONDON N1 9AL',
  'VAT NO. 000 0000 00',
  'TILL 3 SERVED BY: SAM',
  '21/11/2026 08:05:31',
  'EAT IN',
  '1 FLAT WHITE 3.85',
  '1 PORRIDGE 3.50',
  'HONEY',
  '1 CHEDDAR & PICKLE BAGUETTE 5.25',
  '1 STILL WATER 500ML 1.95',
  'TOTAL £14.55',
  'CARD £14.55',
  'AMEX ***********1001',
  'CONTACTLESS  AID A000000025010801',
  'VAT RATE NET VAT GROSS',
  '20.00% 12.13 2.42 14.55',
  'THANK YOU',
  'TELL US HOW WE DID AT',
  'www.example.co.uk/feedback',
];

// ---------------------------------------------------------------- Brazil

/// A Brazilian consumer invoice (NFC-e): a line number and code before
/// each name, "1 UN x 38,90 38,90" on the next row, comma decimals, the
/// date at the bottom after the long access key.
const _brRestaurant = [
  'RESTAURANTE EXEMPLO LTDA',
  'CNPJ: 00.000.000/0001-00  IE: 000.000.000.000',
  'AV PAULISTA 1000 BELA VISTA SAO PAULO SP',
  'DANFE NFC-e - Documento Auxiliar',
  'da Nota Fiscal de Consumidor Eletronica',
  '# COD DESCRICAO QTD UN VL UNIT VL TOTAL',
  '001 1001 PRATO EXECUTIVO FRANGO',
  '1 UN x 38,90 38,90',
  '002 1045 SUCO DE LARANJA 300ML',
  '2 UN x 9,50 19,00',
  '003 1102 CAFE EXPRESSO',
  '1 UN x 6,00 6,00',
  '004 1230 PUDIM DE LEITE',
  '1 UN x 12,00 12,00',
  'QTD. TOTAL DE ITENS 4',
  r'VALOR TOTAL R$ 75,90',
  r'DESCONTO R$ 0,00',
  r'VALOR A PAGAR R$ 75,90',
  'FORMA DE PAGAMENTO VALOR PAGO',
  'CARTAO DE CREDITO 75,90',
  'Consulte pela Chave de Acesso em',
  'www.nfce.fazenda.sp.gov.br',
  '3526 1100 0000 0000 0100 6500 1000 0123 4510 0012 3456',
  'CONSUMIDOR NAO IDENTIFICADO',
  'NFC-e n 000012345 Serie 001 19/11/2026 12:48:05',
  'Protocolo de autorizacao: 135260000000000',
  'Data de autorizacao 19/11/2026 12:48:07',
  r'Tributos Totais Incidentes (Lei Federal 12.741/2012) R$ 14,25',
];

// ------------------------------------------------------------ the checks

/// What a careful person reads off one receipt. A field left null is not
/// asserted (two readings are defensible, or the result has its own test
/// in the group below).
class _Case {
  const _Case(
    this.name,
    this.rows, {
    this.home = 'MXN',
    this.monthFirst = false,
    this.merchant,
    this.date,
    this.amount,
    this.currency,
    this.items,
    this.prices,
  });

  final String name;
  final List<String> rows;

  /// The traveller's currency setting in that country.
  final String home;
  final bool monthFirst;

  /// Acceptable readings of the shop's name, compared without regard to
  /// case; an empty list when no name is printed.
  final List<String>? merchant;

  /// Acceptable dates as "2026-11-18" (more than one only when the receipt
  /// honestly offers two, like a ticket bought before the day of travel).
  final List<String>? date;

  /// The amount paid, in minor units.
  final int? amount;
  final String? currency;

  /// Every line of the items as "description|amount as printed"; a choice
  /// or note under an item has no amount.
  final List<String>? items;

  /// Only the amounts of the priced lines, in order: used instead of
  /// [items] where a name has its own test in the group below.
  final List<String>? prices;
}

ParsedReceipt _parse(
  List<String> rows, {
  String home = 'MXN',
  bool monthFirst = false,
}) =>
    ReceiptTextParser(
      defaultCurrency: home,
      monthFirstDates: monthFirst,
      clock: () => DateTime(2026, 11, 23, 9),
    ).parseRows(rows);

String? _day(DateTime? d) => d == null
    ? null
    : '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

/// A figure as its sign and digits, so that "1,190.00" and "1190.00" (and
/// "1.040,00") compare equal however the reader chooses to tidy them.
String _figure(String? amount) {
  if (amount == null || amount.isEmpty) return '';
  final digits = amount.replaceAll(RegExp(r'\D'), '');
  return (amount.contains('-') ? '-' : '') + digits;
}

String _line(String description, String? amount) =>
    '${description.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim()}'
    '|${_figure(amount)}';

List<String> _items(List<String> rows) => [
      for (final i in ItemLineParser.extract(rows))
        _line(i.description, i.amountText),
    ];

/// The amounts of the priced lines, in order.
List<String> _prices(List<String> rows) => [
      for (final i in ItemLineParser.extract(rows))
        if (i.amountText != null) _figure(i.amountText),
    ];

/// The names of all the lines, in order.
List<String> _names(List<String> rows) => [
      for (final i in ItemLineParser.extract(rows))
        i.description.toUpperCase(),
    ];

List<String> _expectedItems(List<String> lines) => [
      for (final l in lines)
        _line(l.substring(0, l.lastIndexOf('|')),
            l.substring(l.lastIndexOf('|') + 1)),
    ];

const _cases = [
  _Case(
    'Mexico, restaurant bill with a table of suggested tips',
    _mxRestaurantBill,
    merchant: ['La Casa del Ejemplo'],
    date: ['2026-11-18'],
    amount: 98000,
    currency: 'MXN',
    items: [
      'SOPA DE TORTILLA|190.00',
      'ARRACHERA 300G|345.00',
      'ENCHILADAS SUIZAS|185.00',
      'CERVEZA MODELO ESP|130.00',
      'AGUA MINERAL|45.00',
      'FLAN NAPOLITANO|85.00',
    ],
  ),
  _Case(
    'Mexico, restaurant paid by card with the tip',
    _mxRestaurantPaid,
    merchant: ['El Fogon Norteno'],
    date: ['2026-11-20'],
    amount: 281635,
    currency: 'MXN',
    items: [
      'GUACAMOLE C/CHICHARRON|165.00',
      'QUESO FUNDIDO|149.00',
      'RIB EYE 400G|1,190.00',
      'TACOS DE ARRACHERA|245.00',
      'COPA VINO TINTO|495.00',
      'CAFE ESPRESSO|90.00',
      'PASTEL DE ELOTE|115.00',
    ],
  ),
  _Case(
    'Mexico, taqueria order slip with no name printed',
    _mxTaqueriaSlip,
    merchant: [],
    date: ['2026-11-21'],
    amount: 71500,
    currency: 'MXN',
    items: [
      'TACO PASTOR|110.00',
      'TACO SUADERO|66.00',
      'TACO BISTEC C/QUESO|64.00',
      'GRINGA PASTOR|130.00',
      'COSTRA DE QUESO|55.00',
      'ORDEN CEBOLLITAS|40.00',
      'GUACAMOLE CHICO|60.00',
      'AGUA HORCHATA 1L|70.00',
      'REFRESCO|30.00',
      'CERVEZA|90.00',
    ],
  ),
  _Case(
    'Mexico, coffee shop with choices under the drinks',
    _mxCafe,
    merchant: ['Starbucks', 'Starbucks Coffee'],
    date: ['2026-11-19'],
    amount: 29700,
    currency: 'MXN',
    items: [
      'LATTE VENTI|89.00',
      'LECHE DE ALMENDRA|12.00',
      'SHOT EXTRA|',
      'AMERICANO GRANDE|62.00',
      'SIN AZUCAR|',
      'CROISSANT JAMON QUESO|79.00',
      'CALIENTE|',
      'PANQUE DE LIMON|55.00',
    ],
  ),
  _Case(
    'Mexico, fast-food kiosk',
    _mxKiosk,
    merchant: ['Burger King'],
    date: ['2026-11-17'],
    amount: 41800,
    currency: 'MXN',
    items: [
      'COMBO WHOPPER|159.00',
      'PAPAS MEDIANAS|',
      'COCA COLA SIN AZUCAR MED|',
      'COMBO KING DE POLLO|139.00',
      'AROS DE CEBOLLA|',
      'SPRITE MED|',
      'NUGGETS 10 PZ|85.00',
      'SUNDAE CHOCOLATE|35.00',
    ],
  ),
  _Case(
    'Mexico, bar tab in cash with the tip',
    _mxBar,
    merchant: ['Cantina La Ejemplar'],
    date: ['2026-11-20'],
    amount: 180950,
    currency: 'MXN',
    prices: [
      '220.00',
      '165.00',
      '280.00',
      '290.00',
      '175.00',
      '240.00',
      '185.00',
      '90.00',
    ],
  ),
  _Case(
    'Mexico, hotel restaurant charged to a card with the tip',
    _mxHotelRestaurant,
    date: ['2026-11-19'],
    amount: 109250,
    currency: 'MXN',
    items: [
      'BUFFET DESAYUNO|790.00',
      'JUGO VERDE|85.00',
      'CAPUCHINO|75.00',
    ],
  ),
  _Case(
    'Mexico, hotel folio',
    _mxHotelFolio,
    merchant: ['Hotel Ejemplo Centro Historico'],
    date: ['2026-11-19'],
    amount: 845275,
    currency: 'MXN',
  ),
  _Case(
    'Mexico, OXXO',
    _mxOxxo,
    merchant: ['OXXO'],
    date: ['2026-11-22'],
    amount: 22950,
    currency: 'MXN',
    items: [
      'CAFE ANDATTI 16OZ|28.00',
      'SANDWICH JAMON|49.00',
      'AGUA CIEL 1L|34.00',
      'TRIDENT MENTA|18.50',
      'RECARGA TELCEL|100.00',
    ],
  ),
  _Case(
    'Mexico, 7-Eleven',
    _mxSevenEleven,
    merchant: ['7-Eleven', '7 Eleven'],
    date: ['2026-11-18'],
    amount: 14150,
    currency: 'MXN',
    items: [
      'CAFE SELECT 20OZ|32.00',
      'BIG BITE CLASICO|58.00',
      'GATORADE NARANJA 600|27.50',
      'CACAHUATE JAPONES 180G|24.00',
    ],
  ),
  _Case(
    'Mexico, Walmart with weights and discounts',
    _mxWalmart,
    merchant: ['Walmart'],
    date: ['2026-11-21'],
    amount: 71280,
    currency: 'MXN',
  ),
  _Case(
    'Mexico, Chedraui with a 3X2 promotion',
    _mxChedraui,
    merchant: ['Chedraui'],
    date: ['2026-11-22'],
    amount: 50307,
    currency: 'MXN',
    items: [
      'SABRITAS ORIG 170G|54.00',
      'YOGHURT GRIEGO 900G|78.50',
      'ATUN DOLORES AGUA 140G|23.90',
      'ATUN DOLORES AGUA 140G|23.90',
      'ATUN DOLORES AGUA 140G|23.90',
      'PROMOCION 3X2 ATUN|-23.90',
      'QUESO PANELA GRANEL|72.77',
      'TORTILLA MAIZ 1KG|24.00',
      'CERVEZA CORONA 6PK|119.00',
      'SHAMPOO HS 375ML|92.00',
      'BOLSA REUTILIZABLE|15.00',
    ],
  ),
  _Case(
    'Mexico, pharmacy',
    _mxPharmacy,
    merchant: ['Farmacias Guadalajara', 'Farmacia Guadalajara'],
    date: ['2026-11-16'],
    amount: 49260,
    currency: 'MXN',
    items: [
      'PARACETAMOL 500MG 20 TAB|38.50',
      'IBUPROFENO 400MG 10 CAP|90.00',
      'SUERO ELECTROLIT COCO 625|72.00',
      'CURITAS C/20|32.00',
      'PROTECTOR SOLAR FPS50 120ML|289.00',
      'DESCUENTO MONEDERO|-28.90',
    ],
  ),
  _Case(
    'Mexico, Pemex fuel',
    _mxPemex,
    merchant: ['Pemex', 'Gasolinera Ejemplo'],
    date: ['2026-11-21'],
    amount: 91886,
    currency: 'MXN',
  ),
  _Case(
    'Mexico, fuel and oil as a table',
    _mxFuelTable,
    merchant: ['Mobil', 'Servicio Ejemplo del Bajio'],
    date: ['2026-11-20'],
    amount: 97182,
    currency: 'MXN',
    prices: ['782.82', '189.00'],
  ),
  _Case(
    'Mexico, toll booth',
    _mxToll,
    merchant: ['CAPUFE', 'Caminos y Puentes Federales'],
    date: ['2026-11-17'],
    amount: 10400,
    currency: 'MXN',
    items: [],
  ),
  _Case(
    'Mexico, parking',
    _mxParking,
    merchant: ['Estacionamientos Ejemplo'],
    date: ['2026-11-19'],
    amount: 8000,
    currency: 'MXN',
    items: [],
  ),
  _Case(
    'Mexico, duty-free shop priced and paid in dollars',
    _mxAirportShop,
    merchant: ['Dufry'],
    date: ['2026-11-22'],
    amount: 16900,
    currency: 'USD',
    items: [
      'TEQUILA REPOSADO 750ML|62.00',
      'CHOCOLATE TOBLERONE 360G|28.00',
      'PERFUME EDT 50ML|79.00',
    ],
  ),
  _Case(
    'Mexico, card slip alone',
    _mxCardSlip,
    merchant: ['Restaurante El Ejemplo'],
    date: ['2026-11-21'],
    amount: 97750,
    currency: 'MXN',
    items: [],
  ),
  _Case(
    'Mexico, Uber e-mail',
    _mxUber,
    merchant: ['Uber'],
    date: ['2026-11-22'],
    amount: 18743,
    currency: 'MXN',
  ),
  _Case(
    'Mexico, DiDi e-mail',
    _mxDidi,
    merchant: ['DiDi'],
    amount: 9650,
    currency: 'MXN',
    items: [
      'TARIFA BASE|18.00',
      'DISTANCIA|49.00',
      'TIEMPO|24.50',
      'CUOTA DE SERVICIO|5.00',
    ],
  ),
  _Case(
    'Mexico, airline baggage fee',
    _mxBaggage,
    merchant: ['Aeromexico', 'Aeroméxico'],
    date: ['2026-11-22'],
    amount: 139200,
    currency: 'MXN',
  ),
  _Case(
    'Mexico, coach ticket',
    _mxBus,
    merchant: ['ADO'],
    date: ['2026-11-21', '2026-11-23'],
    amount: 37000,
    currency: 'MXN',
    items: [],
  ),
  _Case(
    'Guatemala, cafe',
    _gtCafe,
    home: 'GTQ',
    merchant: ['Cafe Ejemplo Antigua'],
    date: ['2026-11-21'],
    amount: 13000,
    currency: 'GTQ',
    items: [
      'CAPUCHINO|44.00',
      'CAFE AMERICANO|16.00',
      'PASTEL DE ZANAHORIA|28.00',
      'SANDWICH DE POLLO|42.00',
    ],
  ),
  _Case(
    'Guatemala, restaurant with the 10% tip',
    _gtRestaurant,
    home: 'GTQ',
    merchant: ['Restaurante El Ejemplo Chapin'],
    date: ['2026-11-20'],
    amount: 33770,
    currency: 'GTQ',
    items: [
      'PEPIAN DE POLLO|78.00',
      'KAK IK|85.00',
      'GUACAMOL CON TOTOPOS|42.00',
      'CERVEZA GALLO|50.00',
      'LIMONADA CON SODA|22.00',
      'RELLENITOS DE PLATANO|30.00',
    ],
  ),
  _Case(
    'Guatemala, fuel',
    _gtFuel,
    home: 'GTQ',
    merchant: ['Estacion de Servicio Ejemplo', 'Puma Energy', 'Puma'],
    date: ['2026-11-22'],
    amount: 26842,
    currency: 'GTQ',
  ),
  _Case(
    'Guatemala, supermarket',
    _gtSupermarket,
    home: 'GTQ',
    merchant: ['Supermercados La Torre', 'La Torre'],
    date: ['2026-11-19'],
    amount: 10921,
    currency: 'GTQ',
    items: [
      'AGUA PURA SALVAVIDAS 600ML|13.50',
      'FRIJOL NEGRO DUCAL 400G|19.50',
      'PAN SANDWICH BIMBO|21.95',
      'TOMATE MANZANO|7.00',
      'CAFE LEON MOLIDO 350G|38.90',
      'TORTRIX LIMON 180G|12.25',
      'DESCUENTO CLUB|-3.89',
    ],
  ),
  _Case(
    'Guatemala, fried-chicken counter',
    _gtFastFood,
    home: 'GTQ',
    merchant: ['Pollo Campero'],
    date: ['2026-11-22'],
    amount: 13300,
    currency: 'GTQ',
    items: [
      'MENU CAMPERO 3 PIEZAS|62.00',
      'PAPAS FRITAS|',
      'GASEOSA PEPSI 16OZ|',
      'CAMPERITOS 6 UN|39.00',
      'ENSALADA COLESLAW|14.00',
      'PIE DE QUESO|18.00',
    ],
  ),
  _Case(
    'El Salvador, pupuseria in dollars with the tip',
    _svRestaurant,
    home: 'USD',
    merchant: ['Pupuseria La Ejemplar'],
    date: ['2026-11-18'],
    amount: 1925,
    currency: 'USD',
    items: [
      'PUPUSA REVUELTA|5.00',
      'PUPUSA QUESO LOROCO|3.00',
      'YUCA FRITA CON CHICHARRON|4.75',
      'HORCHATA|3.50',
      'CAFE|1.25',
    ],
  ),
  _Case(
    'El Salvador, supermarket',
    _svSupermarket,
    home: 'USD',
    merchant: ['Super Selectos'],
    date: ['2026-11-17'],
    amount: 2125,
    currency: 'USD',
  ),
  _Case(
    'Venezuela, fiscal invoice with IGTF and a dollar reference',
    _veRestaurant,
    home: 'VES',
    merchant: ['Restaurant El Ejemplo', 'Restaurant El Ejemplo, C.A.'],
    date: ['2026-11-19'],
    amount: 369193,
    currency: 'VES',
    items: [
      'AREPA REINA PEPIADA|1.040,00',
      'PABELLON CRIOLLO|1.450,00',
      'JUGO DE PARCHITA|360,00',
      'CAFE MARRON|240,00',
    ],
  ),
  _Case(
    'Venezuela, pharmacy paid by debit card',
    _vePharmacy,
    home: 'VES',
    merchant: ['Farmatodo', 'Farmatodo, C.A.'],
    date: ['2026-11-21'],
    amount: 324938,
    currency: 'VES',
    items: [
      'ACETAMINOFEN 500MG X10|285,00',
      'PROTECTOR SOLAR FPS50|2.150,00',
      'AGUA MINERAL 600ML|95,50',
      'PANUELOS FACIALES X3|310,00',
    ],
  ),
  _Case(
    'Colombia, restaurant in pesos with a voluntary tip',
    _coRestaurant,
    home: 'COP',
    merchant: ['Restaurante El Ejemplo Paisa'],
    date: ['2026-11-18'],
    amount: 13712000,
    currency: 'COP',
    items: [
      'BANDEJA PAISA|42.000',
      'AJIACO SANTAFERENO|36.000',
      'LIMONADA DE COCO|24.000',
      'CERVEZA CLUB COLOMBIA|9.500',
      'POSTRE TRES LECHES|14.000',
    ],
  ),
  _Case(
    'Colombia, supermarket',
    _coSupermarket,
    home: 'COP',
    merchant: ['Exito'],
    date: ['2026-11-20'],
    amount: 5479000,
    currency: 'COP',
    prices: ['2.300', '7.950', '21.900', '9.800', '2.040', '13.500', '-2.700'],
  ),
  _Case(
    'United States, diner with the tip lines left blank',
    _usDiner,
    home: 'USD',
    monthFirst: true,
    merchant: ['Example Street Diner'],
    date: ['2026-11-19'],
    amount: 4731,
    currency: 'USD',
    items: [
      'COFFEE|7.00',
      'PANCAKE STACK|11.50',
      'DENVER OMELETTE|13.95',
      'ADD AVOCADO|2.00',
      'WHEAT TOAST|',
      'SIDE BACON|4.50',
      'ORANGE JUICE LG|4.75',
    ],
  ),
  _Case(
    'United States, drugstore',
    _usDrugstore,
    home: 'USD',
    monthFirst: true,
    merchant: ['CVS Pharmacy', 'CVS'],
    date: ['2026-11-20'],
    amount: 2012,
    currency: 'USD',
    prices: ['8.49', '2.79', '4.58', '4.99', '-2.00'],
  ),
  _Case(
    'United States, pay at the pump',
    _usFuel,
    home: 'USD',
    monthFirst: true,
    merchant: ['Shell', 'Example Fuel Mart', 'Example Fuel Mart #1234'],
    date: ['2026-11-08'],
    amount: 3329,
    currency: 'USD',
  ),
  _Case(
    'United Kingdom, pub with a service charge',
    _ukPub,
    home: 'GBP',
    merchant: ['The Example Arms'],
    date: ['2026-11-18'],
    amount: 8820,
    currency: 'GBP',
    prices: ['12.40', '7.95', '16.50', '15.95', '14.50', '7.50', '3.60'],
  ),
  _Case(
    'United Kingdom, sandwich shop',
    _ukCafe,
    home: 'GBP',
    merchant: ['Pret A Manger', 'Pret'],
    date: ['2026-11-21'],
    amount: 1455,
    currency: 'GBP',
    items: [
      'FLAT WHITE|3.85',
      'PORRIDGE|3.50',
      'HONEY|',
      'CHEDDAR & PICKLE BAGUETTE|5.25',
      'STILL WATER 500ML|1.95',
    ],
  ),
  _Case(
    'Brazil, restaurant NFC-e',
    _brRestaurant,
    home: 'BRL',
    date: ['2026-11-19'],
    amount: 7590,
    currency: 'BRL',
    prices: ['38,90', '19,00', '6,00', '12,00'],
  ),
];

void main() {
  test('there are forty receipts of 20 to 60 rows', () {
    expect(_cases.length, 40);
    for (final c in _cases) {
      expect(c.rows.length, inInclusiveRange(20, 60), reason: c.name);
    }
  });

  group('read end to end', () {
    for (final c in _cases) {
      test(c.name, () {
        final p = _parse(c.rows, home: c.home, monthFirst: c.monthFirst);
        final merchant = c.merchant;
        if (merchant != null && merchant.isEmpty) {
          expect(p.merchant, isNull, reason: 'no shop name is printed');
        } else if (merchant != null) {
          expect(
            [for (final m in merchant) m.toLowerCase()],
            contains(p.merchant?.toLowerCase()),
            reason: 'merchant',
          );
        }
        if (c.date != null) {
          expect(c.date, contains(_day(p.date)), reason: 'date');
        }
        if (c.amount != null) {
          expect(p.amountMinor, c.amount, reason: 'amount');
        }
        if (c.currency != null) {
          expect(p.currency, c.currency, reason: 'currency');
        }
        if (c.items != null) {
          expect(_items(c.rows), _expectedItems(c.items!), reason: 'items');
        }
        if (c.prices != null) {
          expect(
            _prices(c.rows),
            [for (final x in c.prices!) _figure(x)],
            reason: 'prices',
          );
        }
      });
    }
  });

  // Each of these was a clearly wrong result on one of the receipts above
  // when the sweep was first run; all are fixed and kept here apart.
  group('results that were wrong', () {
    // ------------------------------------------------------ the shop's name
    test('Brazil: the shop is the name on the first row', () {
      expect(
        _parse(_brRestaurant, home: 'BRL').merchant?.toLowerCase(),
        startsWith('restaurante exemplo'),
      );
    });

    test('a hotel named after its city is the shop, not "RESTAURANTE"', () {
      expect(
        ['hotel ejemplo cancun', 'hoteles ejemplo de mexico'],
        contains(_parse(_mxHotelRestaurant).merchant?.toLowerCase()),
      );
    });

    // -------------------------------------------------------------- the date
    test('DiDi e-mail: the date "20 nov 2026, 08:14" is read', () {
      expect(_parse(_mxDidi).date, DateTime(2026, 11, 20));
    });

    // ------------------------------------------- items missing or invented
    test('El Salvador: prices followed by the tax letter G are items', () {
      expect(
        _items(_svSupermarket),
        _expectedItems([
          'AGUA CRISTAL 1.5L|1.15',
          'PAN DE CAJA BIMBO|2.85',
          'QUESO DURO BLANDO LB|3.45',
          'CAFE LISTO 50G|2.10',
          'JUGO DEL VALLE NARANJA 1L|1.95',
          'PROTECTOR SOLAR 120ML|9.75',
        ]),
      );
    });

    test('Walmart: a saving under its product does not end the list', () {
      expect(
        _items(_mxWalmart),
        _expectedItems([
          'LECHE LALA ENTERA 1L|27.50',
          'PAN BIMBO BLANCO GDE|45.00',
          'HUEVO BLANCO 18 PZ|62.00',
          'PLATANO CHIAPAS|21.04',
          'JITOMATE SALADET|38.72',
          'PECHUGA POLLO S/H|105.64',
          'COCA COLA 2.5L|84.00',
          'DETERGENTE ARIEL 3KG|149.00',
          'DESCUENTO ARIEL|-30.00',
          'CAFE NESCAFE 225G|132.00',
          'AHORRO CAFE NESCAFE|-12.00',
          'PAPEL HIG REGIO 12R|89.90',
        ]),
      );
    });

    test('hotel folio: every night and every extra is listed', () {
      // The room three times, the restaurant and the laundry, whatever is
      // done with the tax rows printed between them.
      final charges = [
        for (final i in ItemLineParser.extract(_mxHotelFolio))
          if (!RegExp(r'\b(IVA|ISH)\b').hasMatch(i.description))
            _figure(i.amountText),
      ];
      expect(charges, ['215000', '215000', '48500', '215000', '26000']);
    });

    test('Pemex: the product and amount printed after labels are an item', () {
      expect(_items(_mxPemex), _expectedItems(['MAGNA 87 OCT|918.86']));
    });

    test('US pump: the payment row "CREDIT" is not an item', () {
      expect(_names(_usFuel), isNot(contains('CREDIT')));
    });

    test('Guatemala fuel: the fuel tax row "IDP" is not an item', () {
      expect(_prices(_gtFuel), ['26842']);
    });

    test('US drugstore: the count row "5 ITEMS" is not a line', () {
      expect(_names(_usDrugstore), isNot(contains('ITEMS')));
    });

    test('Brazil: the count row "QTD. TOTAL DE ITENS 4" is not a line', () {
      expect(_names(_brRestaurant), hasLength(4));
    });

    // ---------------------------------------------------- names of the items
    test('bar: the measure "1.5OZ" stays in the name', () {
      expect(_names(_mxBar), contains('MEZCAL ESPADIN 1.5OZ'));
    });

    test('fuel table: "30.120 L PREMIUM" is PREMIUM', () {
      expect(_names(_mxFuelTable), ['PREMIUM', 'ACEITE MOBIL SUPER 1L']);
    });

    test('Guatemala fuel: the gallons column is not part of the name', () {
      expect(_names(_gtFuel).first, 'SUPER');
    });

    test('Colombia: the pack size "X3" stays in the name', () {
      final items = ItemLineParser.extract(_coSupermarket);
      expect(_names(_coSupermarket), contains('JABON PROTEX X3'));
      expect(
        [for (final i in items) if (i.quantity == '3') i.description],
        isEmpty,
      );
    });

    test('UK pub: the quantity before "175ML SAUVIGNON BLANC" is split', () {
      expect(_names(_ukPub), contains('175ML SAUVIGNON BLANC'));
    });

    test('Brazil: names without the line number and the product code', () {
      expect(_names(_brRestaurant).take(4).toList(), [
        'PRATO EXECUTIVO FRANGO',
        'SUCO DE LARANJA 300ML',
        'CAFE EXPRESSO',
        'PUDIM DE LEITE',
      ]);
    });
  });
}

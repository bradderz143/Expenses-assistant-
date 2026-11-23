import 'text_normaliser.dart';

/// What a dictionary entry is.
enum _Kind {
  /// A caption before a number or a known word: "FECHA", "FORMA DE PAGO".
  label,

  /// A caption before a name or a code, which stays as printed: "CAJERO:
  /// MARIA", "PLACAS: ABC-123-D".
  name,

  /// A word that is itself the information: "EFECTIVO", "VENTA", "LITROS".
  value,

  /// Kept exactly as printed: "VISA", "MXN", "CHIP".
  printed,
}

class _Entry {
  const _Entry(this.english, this.kind);

  final String english;
  final _Kind kind;
}

/// One printed word or number of a line.
class _Token {
  const _Token.word(this.raw, this.lead, this.trail, this.norm);
  const _Token.printed(this.raw)
      : lead = '',
        trail = '',
        norm = '';

  /// As printed, with its punctuation.
  final String raw;

  /// Punctuation before and after the word: "(", ":", ",".
  final String lead;
  final String trail;

  /// The word in lower case without accents or dots; empty for a number,
  /// an amount, a code or a symbol.
  final String norm;

  bool get isWord => norm.isNotEmpty;
  bool get hasColon => trail.contains(':');

  /// The punctuation to keep after the English: an abbreviation's dot
  /// ("CANT.", "NUM.") goes with the Spanish.
  String get ending => trail.replaceAll('.', '');

  /// A number, an amount, a date, a time or a code.
  bool get isNumber => !isWord && raw.contains(RegExp(r'\d'));
}

class _Hit {
  const _Hit(this.english, this.kind, this.end);

  final String english;
  final _Kind kind;

  /// Index of the token after the phrase.
  final int end;
}

class _Piece {
  _Piece(this.text, this.kind);

  String text;
  final _Kind kind;

  bool get closed => text.endsWith(':') || text.endsWith(',');
}

/// Fixed English for the terse label lines that make up most of a receipt
/// that is not a meal: "FECHA: 14/09/2026" -> "Date: 14/09/2026", "FORMA DE
/// PAGO: EFECTIVO" -> "Payment method: Cash", "BOMBA 4" -> "Pump 4".
///
/// The label comes from a dictionary and the value stays as printed, so
/// nothing depends on the on-device model, which is unreliable on text this
/// short ("Caja 1" -> "Box 1"). A line is only translated when every word of
/// it is known: a line with running Spanish text gives null and goes to the
/// model as before. Written for receipts from Mexico, Guatemala, El
/// Salvador, Venezuela and Colombia.
class ReceiptLabels {
  ReceiptLabels._();

  /// Captions followed by a number, a date or a word from [_valueTable].
  /// English first, then the Spanish wordings separated by "|".
  static const String _labelTable = '''
Date = fecha | fcha
Time = hora
Date and time = fecha y hora | fecha hora
Day = dia
Type = tipo
Details = datos
Validity = vigencia
Valid for = vigente por | valido por | vigencia de
Valid until = valido hasta | vigente hasta | vigencia hasta
Ticket valid for = boleto vigente por | boleto valido por
Expires = vence | vencimiento | caducidad | expira
Period = periodo
From = desde
Until = hasta
Issue = emision | expedicion
Printing = impresion
Certification = certificacion
Opening = apertura
Closing = cierre
Invoicing = facturacion
Total = total
Totals = totales
Subtotal = subtotal | subttl
Total to pay = total a pagar | total por pagar | a pagar
Total due = total a cobrar
Total paid = total pagado
Net total = total neto
Grand total = total general | gran total
Total with tip = total con propina
Total with VAT = total con iva | importe con iva
Total without VAT = total sin iva | importe sin iva
Subtotal without VAT = subtotal sin iva
Price with VAT = precio con iva
Price without VAT = precio sin iva
Total without tip = total sin propina
Total without service = total sin servicio
Total in words = total en letras | total con letra
Amount in words = importe con letra | importe en letra | cantidad con letra | cantidad en letra | valor en letras | monto en letras
Amount = importe | monto
Total amount = importe total | monto total
Net amount = importe neto | monto neto
Gross amount = importe bruto | monto bruto
Amount to pay = importe a pagar | monto a pagar
Amount paid = importe pagado | monto pagado | valor pagado
Amount received = importe recibido | monto recibido
Cash received = efectivo recibido
Total amount of the transaction = monto total de la operacion
Value = valor
Total value = valor total | vr total | vlr total
Unit value = valor unitario | vr unit | vr unitario | vlr unit | vlr unitario | v unitario
Net = neto
Net to pay = neto a pagar
Base = base
Taxable base = base imponible | base gravable | bi
Sums = sumas
Taxable sales = ventas gravadas | venta gravada | vtas gravadas
Exempt sales = ventas exentas | venta exenta | vtas exentas
Non-taxable sales = ventas no sujetas | venta no sujeta | vtas no sujetas
VAT = iva | impuesto al valor agregado | impuesto al valor anadido
VAT included = iva incluido | incluye iva | iva incl
VAT withheld = iva retenido | retencion iva | retencion de iva
VAT charged = iva trasladado
Tax = impuesto | impto
Taxes = impuestos | imptos
Taxes charged = impuestos trasladados | impuesto trasladado
IEPS (excise tax) = ieps
ISR (income tax) = isr
ISR withheld = isr retenido | retencion isr | retencion de isr
Lodging tax = ish | impuesto sobre hospedaje | impuesto hospedaje | impuesto de hospedaje | impuesto al hospedaje
IDP (fuel tax) = idp
IGTF (tax on foreign-currency payments) = igtf
Consumption tax = impoconsumo | impuesto al consumo
Airport fee (TUA) = tua | tarifa de uso de aeropuerto | tasa aeroportuaria
Tourism tax = impuesto de turismo | impuesto turismo | impuesto al turismo | impuesto inguat | inguat
Withholding = retencion | retenciones
Discount = descuento | dcto | dscto | descto
Discounts = descuentos
Total discount = descuento total | total descuento | total descuentos
Total saving = ahorro total | total ahorro | total ahorrado
Saving = ahorro | su ahorro
You saved = usted ahorro | ud ahorro | ahorraste
Surcharge = recargo
Surcharges = recargos
Charge = cargo
Charges = cargos
Service charge = cargo por servicio | cargo de servicio | cargo x servicio
Fuel surcharge = cargo por combustible
Other charges = otros cargos
Taxes and charges = impuestos y cargos | impuestos y derechos
Payment on account = abono
Payments on account = abonos
Advance payment = anticipo
Deposit = deposito
Balance = saldo
Previous balance = saldo anterior
Balance due = saldo pendiente | saldo a pagar | saldo deudor
Current balance = saldo actual | saldo final
Service = servicio
Services = servicios
Tip = propina
Suggested tip = propina sugerida
Tip included = propina incluida
Voluntary tip = propina voluntaria
Change = cambio | vuelto
Your change = su cambio | su vuelto
Payment = pago
Payments = pagos
Your payment = su pago
Paid with = pago con | pagado con | paga con
Received = recibido
Tendered = entregado
Price = precio
Unit price = precio unitario | precio unit | p unitario | p unit | pu | p/u | precio u | prec unit
Price per litre = precio por litro | precio litro | precio x litro | precio lt | precio por lt
Price per gallon = precio por galon | precio galon | precio x galon
Price per night = precio por noche
Cost = costo
Rate|Fare = tarifa
Rate = tasa
Base fare = tarifa base
Starting fare = banderazo
Nightly rate = tarifa por noche | tarifa noche
Hourly rate = tarifa por hora
Daily rate = tarifa diaria | tarifa por dia
Air fare = tarifa aerea
Fee = cuota | comision
Booking fee = cuota de solicitud | cargo por reservacion
Service fee = cuota de servicio | tarifa de servicio
Toll = peaje
Tolls = peajes
Quantity = cantidad
Qty = cant | cantd | ctd | cnt
Items = articulos | arts
Item = articulo
Number of items = no de articulos | numero de articulos | num de articulos | no articulos | num articulos | cantidad de articulos
Items sold = articulos vendidos
Description = descripcion | concepto | detalle
Unit = unidad
Units = unidades
Code = codigo | clave | cod
Exchange rate = tipo de cambio | tipo cambio | t cambio | tasa de cambio | tasa cambio
Exchange rate of the day = tasa del dia
BCV exchange rate = tasa bcv
Currency = moneda | divisa
Payment method = forma de pago | formas de pago | forma pago | f pago | f de pago | metodo de pago | metodo pago | medio de pago | medios de pago | medio pago
Payment terms = condicion de pago | condiciones de pago | cond de pago | condicion pago
Terms of sale = condicion de la operacion | condiciones de la operacion
Term = plazo
Volume = volumen
Pump = bomba
Island = isla
Hose = manguera
Position = posicion
Pump position = posicion de carga
Product = producto
Fuel = combustible
Odometer = odometro
Mileage = kilometraje
Lane = carril
Class = clase
Category = categoria
Opening hours = horario | horario de atencion | horario de servicio
Vehicle = vehiculo
Vehicle class = clase de vehiculo | clase vehiculo | clase vehicular
Crossing = cruce
Entry = entrada
Departure = salida
Arrival = llegada
Duration = tiempo | duracion
Length of stay = tiempo transcurrido | tiempo de estancia | tiempo total | tiempo de permanencia | tiempo estacionado | tiempo de estadia
Stay = estancia | permanencia | estadia
Waiting time = tiempo de espera
Lost ticket = boleto perdido
Grace period = tolerancia
Level = nivel
Floor = piso
Parking = estacionamiento | parqueo
Check-in = check in | checkin
Check-out = check out | checkout
Lodging = hospedaje
Accommodation = alojamiento
Room charge = renta de habitacion | cargo habitacion | cargo de habitacion
Food = alimentos
Drinks = bebidas
Food and drink = alimentos y bebidas | a y b
Restaurant = restaurante
Laundry = lavanderia
Telephone = telefono
Room service = servicio a cuartos | servicio a cuarto | servicio a la habitacion | servicio al cuarto | servicio a habitaciones
Breakfast = desayuno | desayunos
Dinner = cena
Consumption = consumo | consumos
Trip = viaje
Trip total = total del viaje | total viaje
Distance = distancia
Journey = recorrido
Baggage = equipaje
Signature = firma
Name and signature = nombre y firma
Points = puntos
Points earned = puntos acumulados | puntos ganados | puntos obtenidos
Loyalty wallet = monedero | monedero electronico
Instalments = cuotas | parcialidades
Card = tarjeta
Card read method = tipo de lectura | tipo lectura | lectura | modo de entrada | metodo de entrada | modo entrada | modo de lectura
Invoicing model = modelo de facturacion
Transmission = transmision
Generation = generacion
Control = control
Observations = observaciones | observacion | notas | comentarios
Others = otros
Miscellaneous = varios
''';

  /// Captions followed by a name, a place or a code, which is kept as
  /// printed and never translated ("CASETA: LA VENTA" is a place, not a
  /// sale).
  static const String _nameTable = '''
Cashier = cajero | cajera
Salesperson = vendedor | vendedora
Served by = atendio | le atendio | lo atendio | te atendio | atendido por | le atiende | lo atiende | atiende
Waiter = mesero | mesera | mesonero | mozo
Customer = cliente | clte
Name = nombre
Passenger = pasajero
Guest = huesped
Holder = titular
Cardholder = tarjetahabiente | tarjeta habiente
Driver = conductor | chofer
Operator = operador | operadora
Attendant = despachador | despachadora
Employee = empleado
User = usuario
Member = socio
Company name = razon social | nombre o razon social | denominacion | denominacion social
Trading name = nombre comercial
Issuer = emisor
Recipient = receptor
Buyer = comprador
Bank = banco
Issuing bank = banco emisor
Acquirer = adquirente | banco adquirente
Merchant = comercio
Establishment = establecimiento
Branch = sucursal | suc
Store = tienda
Toll plaza = plaza de cobro
Plaza = plaza
Toll booth = caseta
Station = estacion
Service station = estacion de servicio
Origin = origen
Destination = destino
Route = ruta
Section = tramo
Motorway = autopista
City = ciudad
State = estado
Country = pais
Municipality = municipio
Department = departamento
Zone = zona
Address = direccion | domicilio | domicilio fiscal
Postcode = codigo postal | cp
Place of issue = lugar de expedicion | lugar de emision | expedido en
Business activity = giro | actividad economica | actividad
Certifier = certificador
Certificate = certificado
Number plate = placas | placa
Series = serie
Number = numero | num | nro
Fleet No. = numero economico | no economico | num economico
Make = marca
Model = modelo
Colour = color
Line = linea
Airline = aerolinea
Flight = vuelo
Seat = asiento
Row = fila
Service No. = corrida
Platform = anden
Gate = puerta | puerta de embarque | puerta de abordaje
Lounge = sala
Room = habitacion | hab | cuarto
Plan = plan
Table = mesa
Shift = turno
Till = caja
Ticket = ticket | tiquete | tkt | boleto
Transaction = transaccion | trans | trx | operacion | oper
Folio = folio
Invoice = factura | fact
Note = nota
Receipt = recibo | comprobante
Document = documento | docto
Order = pedido | orden
Purchase order = orden de compra
Account = cuenta | cta
Booking = reservacion | reserva
Confirmation = confirmacion
Booking reference = clave de reservacion | codigo de reservacion | clave de reserva | codigo de reserva | localizador
Reference = referencia | ref
Authorisation = autorizacion | aut | autoriz
Approval = aprobacion | aprob
Sequence = secuencia
Batch = lote
Terminal = terminal
Merchant No. = afiliacion
NIT (tax ID) = nit
NRC (taxpayer registration) = nrc
DUI (ID No.) = dui
RFC (tax ID) = rfc
RIF (tax ID) = rif
ID No. = ci | cc | cedula | cedula de identidad | dpi | cui
Tax regime = regimen | regimen fiscal
CFDI use = uso cfdi | uso de cfdi | uso del cfdi
Tax folio (UUID) = folio fiscal
Generation code = codigo de generacion
Reception stamp = sello de recepcion | sello de recibido
Prescription = receta
Doctor = medico
''';

  /// Words that are themselves the information. Written in lower case when
  /// they read as part of a phrase after a number ("2 nights", "35.214
  /// litres"); they get a capital at the start of a line and after a label.
  static const String _valueTable = '''
cash = efectivo | efvo | efect
credit card = tarjeta de credito | tarjeta credito | t credito | t de credito | tdc | tarj credito
debit card = tarjeta de debito | tarjeta debito | t debito | t de debito | tdd | tarj debito
bank card = tarjeta bancaria
card payment = pago con tarjeta | pago tarjeta | pago c/tarjeta
credit card payment = pago con tarjeta de credito | pago tarjeta de credito | pago con tarjeta credito | pago tarjeta credito
debit card payment = pago con tarjeta de debito | pago tarjeta de debito | pago con tarjeta debito | pago tarjeta debito
card payment at the terminal = pago tarjeta c/terminal | pago con tarjeta c/terminal
cash payment = pago en efectivo | pago efectivo
payment in a single instalment = pago en una sola exhibicion | una sola exhibicion
payment in instalments or deferred = pago en parcialidades o diferido | pago en parcialidades
credit = credito | cred
debit = debito | deb
cheque = cheque
bank transfer = transferencia | transferencia bancaria | transferencia electronica | transf
mobile payment = pago movil
voucher = vale
vouchers = vales
food vouchers = vales de despensa
cash sale (paid in full) = contado | de contado | al contado
sale = venta
card sale = venta con tarjeta | venta tarjeta
sales = ventas
total sale = venta total
purchase = compra
refund = devolucion
cancellation = cancelacion
void = anulacion | anulada | anulado
reversal = reverso | reversa
withdrawal = retiro
cash withdrawal = retiro de efectivo
approved = aprobada | aprobado | aceptada | aceptado | autorizada | autorizado
approved online = aprobado en linea | aprobada en linea | autorizado en linea
transaction approved = transaccion aprobada | operacion aprobada | venta aprobada | compra aprobada | pago aprobado | transaccion aceptada | operacion aceptada
transaction successful = operacion exitosa | transaccion exitosa | operacion realizada con exito | transaccion realizada con exito | pago exitoso | compra exitosa | venta exitosa | pago realizado con exito
electronic sale transaction = transaccion electronica de venta
declined = declinada | declinado | rechazada | rechazado | denegada | denegado
cancelled = cancelada | cancelado
pending = pendiente
paid = pagado | pagada
successful = exitosa | exitoso
included = incluido | incluida | incl
not included = no incluido | no incluida
not applicable = no aplica | n/a
yes = si
original = original
copy = copia
duplicate = duplicado
reprint = reimpresion | reimpreso
customer original = original cliente
months interest-free = meses sin intereses | msi
months = meses
month = mes
magnetic stripe = banda | banda magnetica
contactless = sin contacto
PIN = nip
online = en linea
online invoicing = facturacion en linea | facturacion electronica
pesos = pesos
quetzales = quetzales
dollars = dolares | dlls | dls
bolívares = bolivares
colones = colones
lempiras = lempiras
national currency = moneda nacional
litres = litros | lts | ltrs | lt | litro
gallons = galones | gls | gal | galon
km = kilometros | kms
hrs = horas | hrs | hr
min = minutos | mins | min
days = dias
nights = noches
night = noche
adults = adultos
adult = adulto
children = menores | ninos
child = menor | nino
people = personas
guests = huespedes | comensales
passengers = pasajeros
student = estudiante
senior = tercera edad | inapam | adulto mayor
one way = sencillo | viaje sencillo | solo ida
round trip = redondo | viaje redondo | ida y vuelta
outbound = ida
first class = primera clase | primera
economy class = clase turista | turista | clase economica | economica
executive = ejecutivo | ejecutiva
single = sencilla
double = doble
one destination only = un solo destino
pcs = pza | pzas | pz | pzs | piezas | pieza
each = c/u | cada uno
per hour = por hora | x hora | p/hora
per night = por noche | x noche
per day = por dia | x dia
per litre = por litro | x litro
per person = por persona | x persona | p/p
hour or part of an hour = hora o fraccion | hr o fraccion
part of an hour = fraccion
axles = ejes
axle = eje
car = automovil | auto | automoviles | autos | carro
motorcycle = motocicleta | moto
bus = autobus
lorry = camion
pickup = camioneta | pick up
Regular (Magna) = magna
Premium = premium
Diesel = diesel
Regular = regular
Super = super
petrol = gasolina
Regular petrol (Magna) = gasolina magna | pemex magna
premium petrol = gasolina premium | pemex premium
regular petrol = gasolina regular
super petrol = gasolina super
additive = aditivo
oil = aceite
taxable = gravado | gravada | gravados
exempt = exento | exenta | exentos
not subject to tax = no sujeto | no sujetas | no gravado
final consumer = consumidor final
CF (final consumer) = cf | c/f
general public = publico en general | publico general
electronic invoice = factura electronica
electronic sales invoice = factura electronica de venta
electronic tax document = documento tributario electronico
tax credit invoice = comprobante de credito fiscal
final consumer invoice = factura de consumidor final | factura consumidor final
sales invoice = factura de venta
sales receipt = ticket de venta | ticket de compra | tiquete de venta | nota de venta | comprobante de venta
bill = nota de consumo
credit note = nota de credito
payment receipt = recibo de pago | comprobante de pago
transaction receipt = comprobante de operacion | comprobante de transaccion
cash receipt = recibo de caja
credit invoice (factura cambiaria) = factura cambiaria
small taxpayer's invoice = factura pequeno contribuyente | factura de pequeno contribuyente
special taxpayer = contribuyente especial
small taxpayer = pequeno contribuyente
large taxpayer = gran contribuyente | grandes contribuyentes
registered for VAT = responsable de iva | responsable del iva
parking ticket = boleto de estacionamiento
ATM = cajero automatico
complimentary = cortesia
breakfast included = desayuno incluido
frequent customer = cliente frecuente
Monday = lunes | lun
Tuesday = martes | mar
Wednesday = miercoles | mie
Thursday = jueves | jue
Friday = viernes | vie
Saturday = sabado | sab
Sunday = domingo | dom
''';

  /// Card brands, banks, currency codes, units and the English words that
  /// Spanish receipts use: already what an English reader expects.
  static const String _printedWords =
      'visa mastercard master card amex american express carnet electron '
      'maestro discover diners club unionpay bbva banamex citibanamex '
      'santander banorte hsbc scotiabank inbursa bancomer bac banrural '
      'bancolombia davivienda banesco mercantil provincial getnet clip '
      'mxn usd gtq cop ves ved eur gbp hnl crc nio pab mn us q bs bss '
      'kg g gr grs ml l km m cm mts am pm '
      'msr chip emv nfc ctls pin pos tpv qr cfdi sat fel dte pue ppd ok id '
      'sku upc pax vip wifi tv sedan suv taxi hotel suite minibar internet '
      'spa gym online cash tax tip debit credit sale room voucher max';

  /// "FECHA DE EMISION", "TIPO DE PAGO", "NO. DE TICKET", "TOTAL IVA": a
  /// general word joined to another caption. {X} is the English of the
  /// second one ("Issue date", "Payment type", "Ticket No.", "Total VAT").
  static const Map<String, (String, _Kind)> _heads = {
    'fecha': ('{X} date', _Kind.label),
    'fechayhora': ('{X} date and time', _Kind.label),
    'hora': ('{X} time', _Kind.label),
    'tipo': ('{X} type', _Kind.label),
    'numero': ('{X} No.', _Kind.name),
    'num': ('{X} No.', _Kind.name),
    'nro': ('{X} No.', _Kind.name),
    'no': ('{X} No.', _Kind.name),
    'codigo': ('{X} code', _Kind.name),
    'cod': ('{X} code', _Kind.name),
    'clave': ('{X} code', _Kind.name),
    'total': ('Total {x}', _Kind.label),
    'importe': ('{X} amount', _Kind.label),
    'monto': ('{X} amount', _Kind.label),
    'precio': ('{X} price', _Kind.label),
    'costo': ('{X} cost', _Kind.label),
    'nombre': ('{X} name', _Kind.name),
    'firma': ('{X} signature', _Kind.name),
    'copia': ('{X} copy', _Kind.value),
    'datos': ('{X} details', _Kind.label),
  };

  /// Captions that head a column of a table and never describe the caption
  /// before them: "CODIGO DESCRIPCION", "PRECIO IMPORTE" are two headings
  /// each, not a "description code" or an "amount price".
  static const Set<String> _columnOnly = {
    'Description', 'Quantity', 'Qty', 'Amount', 'Price', 'Code', 'Cost', //
    'Value',
  };

  /// Heads that go with a total ("PRECIO TOTAL", "IMPORTE TOTAL"); after the
  /// others "TOTAL" is the next column ("FECHA TOTAL").
  static const Set<String> _moneyHeads = {'precio', 'costo', 'importe', 'monto'};

  /// "No.", "NUM.", "N°" between a caption and its number: "FACTURA No. 12".
  static const Set<String> _numberWords = {'no', 'num', 'nro', 'numero', 'n'};

  static const Map<String, String> _months = {
    'ene': 'Jan', 'enero': 'January', 'feb': 'Feb', 'febrero': 'February', //
    'mar': 'Mar', 'marzo': 'March', 'abr': 'Apr', 'abril': 'April',
    'may': 'May', 'mayo': 'May', 'jun': 'Jun', 'junio': 'June',
    'jul': 'Jul', 'julio': 'July', 'ago': 'Aug', 'agosto': 'August',
    'sep': 'Sep', 'sept': 'Sep', 'set': 'Sep', 'septiembre': 'September',
    'setiembre': 'September', 'oct': 'Oct', 'octubre': 'October',
    'nov': 'Nov', 'noviembre': 'November', 'dic': 'Dec',
    'diciembre': 'December',
  };

  /// Words that show what kind of receipt this is, for the few captions
  /// whose English depends on it.
  static const Set<String> _hotelWords = {
    'habitacion', 'hab', 'huesped', 'huespedes', 'noches', 'noche', //
    'hospedaje', 'hotel',
  };
  static const Set<String> _travelWords = {
    'pasajero', 'pasajeros', 'taxi', 'viaje', 'destino', 'origen', //
    'asiento', 'vuelo', 'corrida', 'banderazo',
  };

  /// Words of running text that no name, place or code is made of.
  static const Set<String> _sentenceWords = {
    'se', 'no', 'por', 'para', 'con', 'sin', 'que', 'es', 'su', 'sus', //
    'este', 'esta', 'un', 'una', 'favor', 'si', 'en',
  };

  static const Set<String> _tollWords = {
    'peaje', 'caseta', 'carril', 'ejes', 'cobro', 'autopista', 'cruce', //
    'capufe',
  };

  static const int _longest = 6;

  /// The dictionary, built once: every Spanish wording under its compact
  /// key, the single words it is made of, and the keys by length (for
  /// finding a phrase one letter away).
  static final ({
    Map<String, _Entry> index,
    Set<String> words,
    Map<int, List<String>> byLength,
    List<String> clashes,
  }) _dictionary = _build();

  static Map<String, _Entry> get _index => _dictionary.index;
  static final Map<String, _Entry?> _nearCache = {};

  static ({
    Map<String, _Entry> index,
    Set<String> words,
    Map<int, List<String>> byLength,
    List<String> clashes,
  }) _build() {
    final index = <String, _Entry>{};
    final vocabulary = <String>{};
    final clashes = <String>[];
    void add(String spanish, _Entry entry) {
      final words = spanish.trim();
      if (words.isEmpty) return;
      final key = _compact(words);
      final before = index[key];
      if (before != null && before.english != entry.english) {
        clashes.add('$words: "${before.english}" / "${entry.english}"');
      }
      index.putIfAbsent(key, () => entry);
      for (final word in words.split(' ')) {
        vocabulary.add(_compact(word));
      }
    }

    void table(String text, _Kind kind) {
      for (final line in text.split('\n')) {
        final at = line.indexOf(' = ');
        if (at < 0) continue;
        final entry = _Entry(line.substring(0, at).trim(), kind);
        for (final spanish in line.substring(at + 3).split('|')) {
          add(spanish, entry);
        }
      }
    }

    table(_labelTable, _Kind.label);
    table(_nameTable, _Kind.name);
    table(_valueTable, _Kind.value);
    for (final word in _printedWords.split(' ')) {
      add(word, const _Entry('', _Kind.printed));
    }
    final byLength = <int, List<String>>{};
    for (final key in index.keys) {
      (byLength[key.length] ??= []).add(key);
    }
    return (
      index: index,
      words: vocabulary,
      byLength: byLength,
      clashes: clashes,
    );
  }

  /// Spanish wordings that the dictionary gives two different meanings:
  /// must be empty (checked by a test).
  static List<String> selfCheck() => List.unmodifiable(_dictionary.clashes);

  /// How many Spanish wordings the dictionary knows.
  static int get size => _index.length;

  /// A word as the dictionary keys it: lower case, no accents, no dots.
  static String _fold(String word) => TextNormaliser.stripDiacritics(word)
      .toLowerCase()
      .replaceAll(RegExp("[.'’°º-]"), '');

  /// A phrase as the index keys it: no spaces, so a word OCR split in two
  /// ("TARJE TA", "SUB TOTAL") still matches, and "l" as "i", the two
  /// letters it mixes up most ("TOTAI", "lMPORTE").
  static String _compact(String phrase) =>
      phrase.split(' ').map(_fold).join().replaceAll('l', 'i');

  static final RegExp _edges =
      RegExp(r'^([(\[¡¿"“*#]*)(.*?)([)\]:;,.!?"”*=]*)$');
  static final RegExp _wordShape = RegExp(
    r"^[A-Za-zÀ-ÖØ-öø-ÿ]+(?:[.'’°º/-]+[A-Za-zÀ-ÖØ-öø-ÿ]+)*[°º]?$",
  );
  static final RegExp _digit = RegExp(r'\d');

  /// "14/SEP/2026", "14-ene-26", "14SEP2026": a date with the month written.
  static final RegExp _monthDate = RegExp(
    r'^(\d{1,2}[-/. ]?)([A-Za-zÀ-ÿ]{3,10})(\.?[-/. ,]?\d{2,4}.*)$',
  );

  /// "14", "2026", "14,": the day or the year beside a written month.
  static final RegExp _dayOrYear = RegExp(r'^\d{1,4}[.,]?$');

  /// "Ticket10001", "CAJA1": a caption with its number stuck to it.
  static final RegExp _glued = RegExp(r'^([A-Za-zÀ-ÿ]{3,})([#$]?\d.*)$');

  static List<_Token> _tokenise(String line) {
    // "FECHA :09/14/2026", "HORA:12:49": the colon after a caption is set
    // apart from the value. A colon between two digits is part of a time.
    final text = TextNormaliser.collapseSpaces(line).replaceAllMapped(
      RegExp(r'(?<=[^\d\s])\s*:\s*(?=\S)'),
      (_) => ': ',
    );
    final out = <_Token>[];
    for (final raw in text.split(' ')) {
      if (raw.isEmpty) continue;
      final m = _edges.firstMatch(raw)!;
      final lead = m[1]!;
      final core = m[2]!;
      final trail = m[3]!;
      if (core.isEmpty) {
        out.add(_Token.printed(raw));
      } else if (_digit.hasMatch(core)) {
        final date = _monthDate.firstMatch(core);
        final month = date == null ? null : _months[_fold(date[2]!)];
        final glued = _glued.firstMatch(core);
        // "T0TAL", "1VA", "EFECTIV0": digits standing for the letters they
        // look like, when that gives a word the dictionary knows.
        final letters = core
            .replaceAll('0', 'o')
            .replaceAll('1', 'i')
            .replaceAll('5', 's')
            .replaceAll('8', 'b');
        if (month != null) {
          out.add(_Token.printed('$lead${date![1]}$month${date[3]}$trail'));
        } else if (core.length >= 3 &&
            _wordShape.hasMatch(letters) &&
            TextNormaliser.letterCount(core) >= 2 &&
            _dictionary.words.contains(_compact(letters))) {
          out.add(_Token.word(raw, lead, trail, _fold(letters)));
        } else if (glued != null &&
            _index[_compact(glued[1]!)] != null &&
            _index[_compact(glued[1]!)]!.kind != _Kind.printed) {
          out.add(_Token.word(glued[1]!, lead, '', _fold(glued[1]!)));
          out.add(_Token.printed('${glued[2]}$trail'));
        } else {
          out.add(_Token.printed(raw));
        }
      } else if (_wordShape.hasMatch(core)) {
        out.add(_Token.word(raw, lead, trail, _fold(core)));
      } else {
        out.add(_Token.printed(raw));
      }
    }
    return out;
  }

  /// Whether [a] and [b] differ by at most one letter added, lost or
  /// changed.
  static bool _oneApart(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    var endA = a.length;
    var endB = b.length;
    while (endA > i && endB > i && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    return endA - i <= 1 && endB - i <= 1;
  }

  /// The one dictionary phrase a letter away from [key], for long phrases
  /// only ("TRANSACCI NELECTRONICA DE VENTA", "AUTORIZACON"): short words
  /// have too many neighbours ("NOCHES" / "COCHES").
  static _Entry? _near(String key) {
    if (key.length < 9) return null;
    return _nearCache.putIfAbsent(key, () {
      _Entry? found;
      for (var length = key.length - 1; length <= key.length + 1; length++) {
        if (length < 9) continue;
        for (final candidate
            in _dictionary.byLength[length] ?? const <String>[]) {
          if (!_oneApart(key, candidate)) continue;
          final entry = _index[candidate]!;
          if (found != null && found.english != entry.english) return null;
          found = entry;
        }
      }
      return found;
    });
  }

  /// The longest dictionary phrase starting at token [i].
  static (_Entry, int)? _phrase(List<_Token> tokens, int i) {
    (_Entry, int)? exact;
    (_Entry, int)? near;
    final buffer = StringBuffer();
    for (var j = i; j < tokens.length && j < i + _longest; j++) {
      final token = tokens[j];
      if (!token.isWord || (j > i && token.lead.isNotEmpty)) break;
      buffer.write(token.norm);
      final key = buffer.toString().replaceAll('l', 'i');
      final entry = _index[key];
      if (entry != null) {
        exact = (entry, j + 1);
      } else if (j == i || token.norm.length > 1) {
        // Not by swallowing a lone letter: in "TOTAL A PAGAR Q 20.00" the
        // "Q" is the currency, not a misprint of "TOTAL A PAGAR".
        final close = _near(key);
        if (close != null) near = (close, j + 1);
      }
      // "TOTAL:", "EFECTIVO,": punctuation ends the phrase.
      if (token.ending.isNotEmpty) break;
    }
    if (near != null && (exact == null || near.$2 > exact.$2)) return near;
    return exact;
  }

  static String _upper(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// "Card" -> "card"; "VAT" and "ISR (income tax)" stay.
  static String _lower(String text) => text.length > 1 &&
          text[1] == text[1].toLowerCase() &&
          text[1] != text[1].toUpperCase()
      ? text[0].toLowerCase() + text.substring(1)
      : text;

  /// The English of [entry] on a receipt that has the words [seen]: the
  /// few captions that mean different things on different receipts.
  static String _sense(_Entry entry, Set<String> seen) {
    final hotel = seen.any(_hotelWords.contains);
    switch (entry.english) {
      // "SALIDA" beside "ENTRADA" is the way out of a car park (or the
      // check-out of a hotel); on its own it is a departure.
      case 'Departure':
        if (!seen.contains('entrada')) return 'Departure';
        return hotel ? 'Check-out' : 'Exit';
      case 'Entry':
        return hotel ? 'Check-in' : 'Entry';
      // A taxi, bus or flight has a fare; a car park or a hotel a rate.
      case 'Rate|Fare':
        return seen.any(_travelWords.contains) ? 'Fare' : 'Rate';
      // "PLAZA: 104 TEPOTZOTLAN" on a toll ticket is the toll plaza; on a
      // bank slip or a shop's ticket "PLAZA" is the town or the shopping
      // centre, and stays "Plaza".
      case 'Plaza':
        return seen.any(_tollWords.contains) ? 'Toll plaza' : 'Plaza';
    }
    return entry.english;
  }

  /// The dictionary phrase or the joined caption ("FECHA DE EMISION")
  /// starting at token [i], whichever is longer.
  ///
  /// [heading] says that a caption with no value comes right before, as in
  /// a row of column headings.
  static _Hit? _match(
    List<_Token> tokens,
    int i,
    Set<String> seen, {
    bool heading = false,
  }) {
    final plain = _phrase(tokens, i);
    _Hit? joined;
    final buffer = StringBuffer();
    for (var j = i; j < tokens.length && j < i + 3; j++) {
      final token = tokens[j];
      if (!token.isWord || (j > i && token.lead.isNotEmpty)) break;
      buffer.write(token.norm);
      final head = _heads[buffer.toString()];
      if (token.ending.isNotEmpty) break;
      if (head == null) continue;
      var k = j + 1;
      var tied = false;
      if (k < tokens.length && const {'de', 'del'}.contains(tokens[k].norm)) {
        tied = true;
        k++;
        if (k < tokens.length &&
            const {'la', 'el', 'los', 'las'}.contains(tokens[k].norm)) {
          k++;
        }
      }
      var second = k < tokens.length ? _phrase(tokens, k) : null;
      // "TIPO PAGO EFECTIVO" is "TIPO PAGO" and its value, not the type of
      // a "PAGO EFECTIVO": a caption right after the head goes with it.
      if (second != null && second.$1.kind == _Kind.value && second.$2 > k + 1) {
        final caption = _phrase(tokens.sublist(0, k + 1), k);
        if (caption != null &&
            (caption.$1.kind == _Kind.label || caption.$1.kind == _Kind.name)) {
          second = caption;
        }
      }
      if (second == null || second.$1.kind == _Kind.printed) continue;
      if (_columnOnly.contains(second.$1.english) ||
          (const {'Total', 'Subtotal'}.contains(second.$1.english) &&
              !_moneyHeads.contains(buffer.toString()))) {
        continue;
      }
      // "NO" is also "not" ("NO PAGADO"): only "de" or a caption after it
      // makes it a number.
      final counted = second.$1.kind == _Kind.value;
      if (buffer.toString() == 'no' && counted && !tied) continue;
      // Without "de" the two may be neighbours in a row of column headings
      // ("FECHA CONCEPTO CARGOS ABONOS", "DESCRIPCION PRECIO UNIDAD"): one
      // caption only when no heading comes before it and its value, a colon
      // or the end of the line follows ("FECHA EMISION: 14/09", "NUM. TICKET
      // 4521", "TIPO PAGO EFECTIVO").
      if (!tied && heading) continue;
      if (!tied &&
          tokens[second.$2 - 1].ending.isEmpty &&
          second.$2 < tokens.length &&
          tokens[second.$2].isWord) {
        final after = _phrase(tokens, second.$2);
        if (after == null ||
            after.$1.kind == _Kind.label ||
            after.$1.kind == _Kind.name) {
          continue;
        }
      }
      final english = _sense(second.$1, seen);
      // "NUMERO DE HABITACION" is the room's number; "NUMERO DE NOCHES",
      // "NO. DE PASAJEROS" and "NUM. DE CUOTAS" say how many.
      final howMany = _numberWords.contains(buffer.toString()) &&
          (counted ||
              (second.$1.kind == _Kind.label && english.endsWith('s')));
      joined = _Hit(
        howMany
            ? 'Number of ${_lower(english)}'
            : head.$1
                .replaceAll('{X}', _upper(english))
                .replaceAll('{x}', _lower(english)),
        howMany ? _Kind.label : head.$2,
        second.$2,
      );
    }
    if (joined != null && (plain == null || joined.end > plain.$2)) {
      return joined;
    }
    if (plain != null) {
      return _Hit(_sense(plain.$1, seen), plain.$1.kind, plain.$2);
    }
    // "FECHA/HORA", "ENTRADA/SALIDA": two captions with a stroke between.
    final token = tokens[i];
    if (token.norm.contains('/')) {
      final parts = <String>[];
      var kind = _Kind.label;
      for (final part in token.norm.split('/')) {
        final entry = _index[part.replaceAll('l', 'i')];
        if (entry == null || entry.kind == _Kind.printed) return null;
        if (parts.isEmpty) kind = entry.kind;
        parts.add(_upper(_sense(entry, seen)));
      }
      return _Hit(parts.join('/'), kind, i + 1);
    }
    return null;
  }

  /// Whether [row] is one caption and nothing else: "TOTAL", "TOTAL A
  /// PAGAR", "FECHA", "EFECTIVO".
  static bool isCaption(String row) {
    final tokens = _tokenise(row);
    if (tokens.isEmpty || tokens.length > 4) return false;
    if (tokens.any((t) => !t.isWord)) return false;
    final hit = _match(tokens, 0, _wordsOf([row]));
    return hit != null && hit.end == tokens.length && hit.kind != _Kind.printed;
  }

  /// The words of [lines] that the dictionary may need to choose a sense.
  static Set<String> _wordsOf(Iterable<String> lines) => {
        for (final line in lines)
          for (final token in _tokenise(line))
            if (token.isWord) ...token.norm.split('/'),
      };

  /// [translate] for every line of one receipt, each read in the light of
  /// the others ("SALIDA" is an exit when the receipt also has "ENTRADA").
  static List<String?> translateAll(List<String> lines, String language) {
    if (language != 'es') return List.filled(lines.length, null);
    final seen = _wordsOf(lines);
    return [for (final line in lines) translate(line, language, seen: seen)];
  }

  /// The English for [line], or null when it is not a label line: a word
  /// the dictionary does not know, or running text after the label. [seen]
  /// is the receipt's other wording, when known.
  static String? translate(String line, String language, {Set<String>? seen}) {
    if (language != 'es') return null;
    final tokens = _tokenise(line);
    if (tokens.isEmpty) return null;
    final context = seen ?? _wordsOf([line]);
    final pieces = <_Piece>[];
    var translated = false;
    var i = 0;
    while (i < tokens.length) {
      final token = tokens[i];
      final before = pieces.isEmpty ? null : pieces.last;
      final next = i + 1 < tokens.length ? tokens[i + 1] : null;
      if (!token.isWord) {
        pieces.add(_Piece(token.raw, _Kind.printed));
        i++;
        continue;
      }
      final captionBefore = before != null &&
          (before.kind == _Kind.label || before.kind == _Kind.name) &&
          !before.closed;
      // "FACTURA No. 123", "FOLIO NUM: 45": the number sign after a caption.
      if (_numberWords.contains(token.norm) &&
          captionBefore &&
          (token.hasColon || (next != null && next.isNumber))) {
        pieces.add(_Piece('No.${token.ending}', _Kind.printed));
        i++;
        continue;
      }
      // "PROPINA INCLUIDA: NO".
      if (token.norm == 'no' && next == null && before != null && before.closed) {
        pieces.add(_Piece('No${token.ending}', _Kind.value));
        i++;
        continue;
      }
      // "14 SEP 2026", "14 DE SEPTIEMBRE DE 2026": a month beside a number,
      // and the "de" that ties the date together.
      // Beside a whole date the same letters are a weekday ("MAR 15/09/2026"
      // is a Tuesday, not March).
      final month = _months[token.norm];
      final afterNumber = i > 0 && tokens[i - 1].isNumber;
      final dated = (afterNumber && _dayOrYear.hasMatch(tokens[i - 1].raw)) ||
          (next != null && _dayOrYear.hasMatch(next.raw)) ||
          (i > 1 &&
              tokens[i - 1].norm == 'de' &&
              _dayOrYear.hasMatch(tokens[i - 2].raw));
      if (month != null && dated) {
        pieces.add(_Piece('${token.lead}$month${token.ending}', _Kind.printed));
        translated = true;
        i++;
        continue;
      }
      if ((token.norm == 'de' || token.norm == 'del') && next != null) {
        final monthBefore = i > 0 && _months.containsKey(tokens[i - 1].norm);
        if ((afterNumber && _months.containsKey(next.norm)) ||
            (monthBefore && next.isNumber)) {
          i++;
          continue;
        }
      }
      // "DEL 14/09/2026 AL 16/09/2026", "ESTANCIA DEL 14/09 AL 16/09".
      if (next != null && next.isNumber) {
        if (const {'del', 'de'}.contains(token.norm) &&
            (before == null || before.closed || before.kind == _Kind.label)) {
          pieces.add(_Piece(
            before == null || before.closed ? 'From' : 'from',
            _Kind.printed,
          ));
          translated = true;
          i++;
          continue;
        }
        if (const {'al', 'a'}.contains(token.norm) && afterNumber) {
          pieces.add(_Piece('to', _Kind.printed));
          translated = true;
          i++;
          continue;
        }
      }
      final hit = _match(tokens, i, context, heading: captionBefore);
      if (hit == null) {
        // A lone letter is a code or a sign ("CLASE B", "2 X 45.00"), unless
        // it is a Spanish word ("IVA Y PROPINA", "PAGO A CREDITO"): a vowel
        // is a code only between a caption and the end of the line, a number
        // or the next caption ("SERIE A FOLIO 12345", "CLASE: A").
        final vowel = const {'a', 'e', 'o', 'u', 'y'}.contains(token.norm);
        final afterCaption = before != null &&
            (before.kind == _Kind.label || before.kind == _Kind.name);
        if (token.norm.length == 1 &&
            (!vowel ||
                (token.norm != 'y' &&
                    afterCaption &&
                    (next == null ||
                        next.isNumber ||
                        _startsCaption(tokens, i + 1, context))))) {
          pieces.add(_Piece(token.raw, _Kind.printed));
          i++;
          continue;
        }
        return null;
      }
      final first = token;
      final last = tokens[hit.end - 1];
      if (hit.kind == _Kind.printed) {
        for (var k = i; k < hit.end; k++) {
          pieces.add(_Piece(tokens[k].raw, _Kind.printed));
        }
        i = hit.end;
        continue;
      }
      translated = true;
      var english = hit.english;
      if (hit.kind == _Kind.value) {
        // Two such words in a row ("VENTA CONTADO") depend on Spanish word
        // order: left to the model. Not after a quantity and its unit, which
        // read the same way in English ("35.214 LTS MAGNA 844.78").
        if (before != null && before.kind == _Kind.value && !before.closed) {
          final quantity = pieces.length >= 2 &&
              pieces[pieces.length - 2].kind == _Kind.printed &&
              _digit.hasMatch(pieces[pieces.length - 2].text);
          if (!quantity) return null;
        }
        final opens = before == null ||
            before.closed ||
            before.kind == _Kind.label ||
            before.kind == _Kind.name ||
            last.hasColon;
        if (opens) english = _upper(english);
        // "FORMA DE PAGO EFECTIVO", "HABITACION DOBLE": the colon the
        // printer left out.
        if (before != null &&
            (before.kind == _Kind.label || before.kind == _Kind.name) &&
            !before.closed) {
          before.text = '${before.text}:';
        }
      }
      pieces.add(_Piece('${first.lead}$english${last.ending}', hit.kind));
      i = hit.end;
      if (hit.kind != _Kind.name || !last.hasColon) continue;

      // After "CAJERO:", "ORIGEN:", "PLACAS:" comes a name, a place or a
      // code: kept as printed up to the next caption on the row.
      var end = i;
      while (end < tokens.length) {
        if (end > i && _startsCaption(tokens, end, context)) break;
        end++;
      }
      if (end == i) continue;
      final words = [for (var k = i; k < end; k++) if (tokens[k].isWord) k];
      if (words.length > 6) return null;
      final whole = _phrase(tokens, i);
      if (whole != null &&
          whole.$2 == end &&
          whole.$1.kind == _Kind.value &&
          tokens[i].lead.isEmpty) {
        // "CLIENTE: PUBLICO EN GENERAL", "NIT: CF".
        pieces.add(_Piece(
          '${_upper(whole.$1.english)}${tokens[end - 1].ending}',
          _Kind.value,
        ));
      } else {
        // "NOTA: NO SE ACEPTAN DEVOLUCIONES": a sentence, not a name.
        if (words.any((k) => _sentenceWords.contains(tokens[k].norm))) {
          return null;
        }
        for (var k = i; k < end; k++) {
          pieces.add(_Piece(tokens[k].raw, _Kind.printed));
        }
      }
      i = end;
    }
    if (!translated) {
      // "VISA", "MINIBAR 95.00", "TAXI": nothing to translate, but a line of
      // words that English shares reads the same in English.
      final shared = tokens.any((t) =>
          t.isWord &&
          t.norm.length >= 3 &&
          _index[t.norm.replaceAll('l', 'i')]?.kind == _Kind.printed);
      if (!shared) return null;
    }
    // "(1 MESES SIN INTERESES )": no gap inside the brackets.
    return pieces
        .map((p) => p.text)
        .join(' ')
        .replaceAll('( ', '(')
        .replaceAll(' )', ')');
  }

  /// Whether a new "CAPTION: value" pair starts at token [i]: a caption
  /// with a colon or a number after it ("… CAJA: 3", "… MESA 4").
  static bool _startsCaption(List<_Token> tokens, int i, Set<String> seen) {
    if (!tokens[i].isWord) return false;
    final hit = _match(tokens, i, seen);
    if (hit == null) return false;
    if (hit.kind != _Kind.label && hit.kind != _Kind.name) return false;
    if (tokens[hit.end - 1].hasColon) return true;
    return hit.end < tokens.length && tokens[hit.end].isNumber;
  }
}

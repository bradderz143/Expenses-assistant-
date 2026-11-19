import 'package:expense_assistant/domain/logic/amount_in_words.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WordsAmount? one(List<String> rows) {
    final found = AmountInWords.find(rows);
    return found.isEmpty ? null : found.first;
  }

  void expectAmount(String row, int whole, int? cents) {
    final amount = one([row]);
    expect(amount, isNotNull, reason: row);
    expect(amount!.whole, whole, reason: row);
    expect(amount.cents, cents, reason: row);
    expect(amount.formal, isTrue, reason: row);
    expect(amount.exact, isTrue, reason: row);
  }

  test('Spanish amounts as receipts print them', () {
    expectAmount('(**TRES MIL SETECIENTOS SESENTA PESOS 00/100 **)', 3760, 0);
    expectAmount('(CUATROCIENTOS VEINTIOCHO PESOS 50/100 M.N.)', 428, 50);
    expectAmount('IMPORTE CON LETRA: UN MIL DOSCIENTOS PESOS 00/100 MN', 1200, 0);
    expectAmount('SON: OCHENTA Y CINCO MIL PESOS M/CTE', 85000, null);
    expectAmount('SON: CIENTO VEINTE Y 50/100 SOLES', 120, 50);
    expectAmount('SON PESOS: UN MIL DOSCIENTOS CON 00/100', 1200, 0);
    expectAmount(
        'SETENTA MIL DOSCIENTOS SETENTA Y OCHO BOLIVARES CON 80/100', 70278, 80);
    expectAmount('DOSCIENTOS PESOS CON CINCUENTA CENTAVOS', 200, 50);
    expectAmount('CIEN PESOS 00/100 M.N.', 100, 0);
    expectAmount('VEINTIUN MIL QUINIENTAS LEMPIRAS 00/100', 21500, 0);
    expectAmount('UN MILLON DOSCIENTOS MIL BOLIVARES CON 05/100', 1200000, 5);
    expectAmount('DIEZ Y SEIS PESOS 00/100', 16, 0);
    expectAmount('SON: QUINIENTOS QUETZALES EXACTOS', 500, null);
  });

  test('English and Portuguese', () {
    expectAmount(
      'Amount in words: Three Thousand Seven Hundred and Sixty Naira Only',
      3760,
      null,
    );
    expectAmount('Rupees Four Hundred Twenty Only', 420, null);
    expectAmount('SAY: ONE THOUSAND TWO HUNDRED CEDIS', 1200, null);
    expectAmount('Forty-Five Dollars and 50/100', 45, 50);
    expectAmount('Twelve Pounds and Thirty Pence', 12, 30);
    expectAmount('Rupees One Lakh Twenty Thousand Only', 120000, null);
    expectAmount('TREZENTOS E SESSENTA E CINCO REAIS E 40/100', 365, 40);
  });

  test('zeros read as letters in the cents', () {
    expectAmount('TRES MIL SETECIENTOS SESENTA PESOS OO/1OO', 3760, 0);
    expectAmount('TRES MIL SETECIENTOS SESENTA PESOS 00/l00', 3760, 0);
  });

  test('a missing or stray space inside the words', () {
    expectAmount('TRESMIL SETECIENTOS SESENTA PESOS 00/100', 3760, 0);
    expectAmount('TRES MIL SETEC IENTOS SESENTA PESOS 00/100', 3760, 0);
  });

  test('wrapped over two rows is read once, whole', () {
    final found = AmountInWords.find([
      r'TOTAL $123,456.78',
      '(CIENTO VEINTITRES MIL CUATROCIENTOS',
      'CINCUENTA Y SEIS PESOS 78/100 M.N.)',
    ]);
    expect(found, hasLength(1));
    expect(found.single.whole, 123456);
    expect(found.single.cents, 78);
    expect(found.single.exact, isTrue);
  });

  test('a damaged word is guessed only when one number fits, and says so', () {
    final guessed = one(['TRES MIL SETECIENTCS SESENTA PESOS 00/100']);
    expect(guessed!.whole, 3760);
    expect(guessed.exact, isFalse);

    // "SE1ENTA" could be sesenta or setenta: no reading at all.
    expect(one(['TRES MIL SETECIENTOS SE1ENTA PESOS 00/100']), isNull);
  });

  test('half a phrase is never read as a smaller number', () {
    // The damaged word cuts the phrase in two; neither half is the amount.
    expect(one(['TRES MIL S#T#C##NT#S SESENTA PESOS 00/100']), isNull);
    expect(one(['TRES MIL ECIENTOS SESENTA PESOS 00/100']), isNull);
    expect(one(['(** IRES MIL SETECIENTOS SESENTA PESOS 00/100 **)']), isNull);
    // Second row of a wrap whose first row is damaged.
    final found = AmountInWords.find([
      '(** TRES MIL S#T#C##NT#S',
      'SESENTA PESOS 00/100 **)',
    ]);
    expect(found.where((w) => w.exact), isEmpty);

    // Digits standing in for letters are put back, as a guess.
    final repaired = one(['TRES M1L SE7EC1EN7OS SESENTA PESOS 00/100']);
    expect(repaired!.whole, 3760);
    expect(repaired.exact, isFalse);
  });

  test('number words that are not an amount due', () {
    for (final row in [
      'PASTEL TRES LECHES 140.00',
      'PIZZA CUATRO QUESOS 189.00',
      '2 DOS EQUIS 110.00',
      'AV. CINCO DE MAYO 123',
      'CALLE VEINTE DE NOVIEMBRE 15',
      'MIL HOJAS 85.00',
      'GANA MIL PESOS',
      'GANA CIEN MIL PESOS EN PREMIOS',
      'CANTIDAD: DOS',
      'BUY ONE GET ONE FREE',
      'TWO POUNDS OFF',
      'SON DOS',
    ]) {
      expect(one([row]), isNull, reason: row);
    }
    // Words and a currency with nothing that marks an amount due ("00/100",
    // "SON:") are read, but only ever to back up a figure.
    final bare = one(['TRES MIL SETECIENTOS SESENTA PESOS']);
    expect(bare!.whole, 3760);
    expect(bare.formal, isFalse);
  });

  test('matching against figures', () {
    const withCents = WordsAmount(whole: 3760, cents: 0, exact: true, formal: true);
    expect(withCents.matches(376000, 2), isTrue);
    expect(withCents.matches(376050, 2), isFalse);
    expect(withCents.toMinor(2), 376000);
    const noCents = WordsAmount(whole: 85000, exact: true, formal: true);
    expect(noCents.matches(8500000, 2), isTrue);
    expect(noCents.matches(8500050, 2), isTrue); // cents not stated
    expect(noCents.matches(85000, 0), isTrue);
    const half = WordsAmount(whole: 12, cents: 500 ~/ 10, exact: true, formal: true);
    expect(half.toMinor(3), 12500);
    expect(half.toMinor(0), 12);
  });
}

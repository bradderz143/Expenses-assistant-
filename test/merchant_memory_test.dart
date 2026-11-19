import 'package:expense_assistant/domain/logic/merchant_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = 'PRECUENTA\nCAFE EJEMPLO\nNIT: 0000-000000-000-1\nTEL: 00000000\n'
      'CAJA: 19 30/09/2026 12:49\nTOTAL 31.42';

  test('learns ids, the wrong guess and the name', () {
    final clues = MerchantMemory.learn(
      ocrText: first,
      merchant: 'Cafe Ejemplo',
      wrongGuess: 'Precuenta',
    );
    final kinds = {for (final c in clues) c.kind: c.key};
    expect(kinds[ClueKind.id], '00000000000001');
    expect(kinds[ClueKind.guess], 'precuenta');
    expect(kinds[ClueKind.printed], 'cafe ejemplo');
    // The all-zero phone number is not an id.
    expect(clues.where((c) => c.key == '00000000'), isEmpty);
  });

  test('recalls by tax id even when the name is not printed', () {
    final memory = MerchantMemory.learn(ocrText: first, merchant: 'Cafe Ejemplo');
    expect(
      MerchantMemory.recall(
        ocrText: 'NIT 0000-000000-000-1\nTOTAL 12.00',
        guess: 'Something Else',
        memory: memory,
      ),
      'Cafe Ejemplo',
    );
  });

  test('recalls when the name appears anywhere', () {
    final memory = MerchantMemory.learn(ocrText: '', merchant: 'Cafe Ejemplo');
    expect(
      MerchantMemory.recall(
        ocrText: 'Bienvenidos\nCafe Ejemplo San Benito\nTOTAL 9.00',
        guess: 'Bienvenidos',
        memory: memory,
      ),
      'Cafe Ejemplo',
    );
    expect(
      MerchantMemory.recall(
        ocrText: 'OTRO SITIO\nTOTAL 9.00',
        guess: 'Otro Sitio',
        memory: memory,
      ),
      isNull,
    );
  });
}

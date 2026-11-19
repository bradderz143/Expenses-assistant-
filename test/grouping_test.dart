import 'package:expense_assistant/domain/entities/enums.dart';
import 'package:expense_assistant/domain/logic/item_classifier.dart';
import 'package:expense_assistant/domain/reference/countries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifier separates drinks from food', () {
    expect(ItemClassifier.classify('COCA ZERO BOT'), ItemCategory.drink);
    expect(ItemClassifier.classify('PARIS WARM BOWL'), ItemCategory.food);
  });

  test('reconcile maps confusable languages back to expected', () {
    expect(Languages.reconcile('gl', 'es'), 'es');
    expect(Languages.reconcile('en', 'es'), 'en');
  });
}

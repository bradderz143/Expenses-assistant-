import '../entities/enums.dart';

/// Oracle expense types. Strings must match Oracle exactly so the claim
/// summary can be copied straight across.
class ClaimTaxonomy {
  ClaimTaxonomy._();

  static const List<String> expenseCategories = [
    'Accommodation Overseas',
    'Accommodation UK',
    'Meals Overseas',
    'Meals UK',
    'Non Project Meals UK',
    'Travel Overseas Taxi',
    'Travel Overseas Car Hire/Fuel',
    'Travel Overseas Other',
    'Travel UK Taxi',
    'Travel UK Train',
    'Travel UK Bus',
    'Travel UK Car Hire/Fuel',
    'Travel UK Car Parking',
    'Travel UK Other',
    'Excess Baggage Charges',
    'Laundry',
    'Entertainment',
    'Professional Subscriptions',
    'Training Accommodation',
    'Training Travel',
    'Training Meals',
    'Training Conference Fees',
    'Training Business Specific',
    'Training Further Education',
    'UK Mileage',
    'Overseas Mileage',
    'Visas',
    'ATM Cash Withdrawal',
    'Bank Charges',
    'WFH Office Equipment',
  ];

  static const List<String> travelPackageCategories = [
    'TP Flights',
    'TP Rail',
    'TP Bus',
    'TP Ferry',
    'TP Mileage',
    'TP Road Tolls',
    'TP CI Adjustments',
  ];

  static List<String> categoriesFor(ClaimType type) => switch (type) {
        ClaimType.expense => expenseCategories,
        ClaimType.travelPackage => travelPackageCategories,
      };

  static bool isValidCategory(ClaimType type, String? category) =>
      category != null && categoriesFor(type).contains(category);

  /// The brief: meal type is captured only when the category contains "Meals".
  static bool isMealCategory(String? category) =>
      category != null && category.contains('Meals');
}

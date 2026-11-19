import '../entities/enums.dart';

/// Smart default for the meal-type selector. The user always confirms it.
class MealTypeGuesser {
  MealTypeGuesser._();

  static MealType fromTime(int hour, int minute) {
    final minutes = hour * 60 + minute;
    if (minutes < 11 * 60) return MealType.breakfast;
    if (minutes < 16 * 60 + 30) return MealType.lunch;
    return MealType.dinner;
  }

  /// Accepts `HH:mm`. Returns null for anything unparseable.
  static MealType? fromTimeString(String? hhmm) {
    if (hhmm == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm);
    if (m == null) return null;
    return fromTime(int.parse(m[1]!), int.parse(m[2]!));
  }
}

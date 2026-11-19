/// Locale-independent formatting used in generated files, so evidence packs
/// look the same whatever the phone's language is.
class Formatting {
  Formatting._();

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `2026-11-04`
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// `04 Nov 2026`
  static String displayDate(DateTime d) =>
      '${_two(d.day)} ${_months[d.month - 1]} ${d.year}';

  /// `Nov_2026`
  static String monthYear(DateTime d) => '${_months[d.month - 1]}_${d.year}';

  static DateTime? parseIsoDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

import '../services/services.dart';

/// A visual row on the receipt, made of one or more OCR lines that sit at the
/// same height (e.g. "TACOS AL PASTOR" on the left and "90.00" on the right).
class OcrRow {
  const OcrRow(this.segments);

  final List<OcrLine> segments;

  String get text => segments.map((s) => s.text.trim()).join('  ');

  double get left => segments.map((s) => s.left).reduce(_min);
  double get top => segments.map((s) => s.top).reduce(_min);
  double get right => segments.map((s) => s.right).reduce(_max);
  double get bottom => segments.map((s) => s.bottom).reduce(_max);

  static double _min(double a, double b) => a < b ? a : b;
  static double _max(double a, double b) => a > b ? a : b;

  double get height {
    var max = 0.0;
    for (final s in segments) {
      if (s.height > max) max = s.height;
    }
    return max;
  }
}

/// ML Kit returns text in blocks, and receipts are laid out in columns, so an
/// item and its price usually arrive in different blocks. This regroups the
/// lines into rows by vertical overlap and orders each row left to right.
class OcrRowAssembler {
  OcrRowAssembler._();

  /// Lines whose vertical overlap is at least this fraction of the shorter
  /// line's height are treated as the same row.
  static const double overlapThreshold = 0.5;

  static List<OcrRow> assemble(List<OcrLine> lines) {
    final usable = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (usable.isEmpty) return const [];
    if (usable.any((l) => !l.hasGeometry)) {
      // No boxes (e.g. plain text in tests): keep reading order.
      return [for (final l in usable) OcrRow([l])];
    }
    // Two receipts photographed side by side: read each on its own, left
    // one first, so their rows do not run into each other.
    final sides = _splitSideBySide(usable);
    if (sides != null) {
      return [..._rowsOf(sides.$1), ..._rowsOf(sides.$2)];
    }
    return _rowsOf(usable);
  }

  /// Splits [lines] into a left and a right receipt when an empty vertical
  /// band separates two blocks that each look like a receipt of their own:
  /// several long lines on both sides. (A column of short prices beside a
  /// column of descriptions is not one.) Null when there is no such band.
  static (List<OcrLine>, List<OcrLine>)? _splitSideBySide(List<OcrLine> lines) {
    if (lines.length < 10) return null;
    final heights = [for (final l in lines) l.height]..sort();
    final lineHeight = heights[heights.length ~/ 2];
    final byLeft = [...lines]..sort((a, b) => a.left.compareTo(b.left));
    final minGap = lineHeight * 1.0;
    final longLine = lineHeight * 8;

    var reach = byLeft.first.right;
    double? bestGap;
    int? bestAt;
    for (var i = 1; i < byLeft.length; i++) {
      final gap = byLeft[i].left - reach;
      if (gap >= minGap && i >= lines.length * 0.3 && i <= lines.length * 0.7) {
        final left = byLeft.sublist(0, i);
        final right = byLeft.sublist(i);
        bool receiptLike(List<OcrLine> side) =>
            side.where((l) => l.right - l.left >= longLine).length >= 4;
        if (receiptLike(left) &&
            receiptLike(right) &&
            (bestGap == null || gap > bestGap)) {
          bestGap = gap;
          bestAt = i;
        }
      }
      if (byLeft[i].right > reach) reach = byLeft[i].right;
    }
    if (bestAt == null) return null;
    return (byLeft.sublist(0, bestAt), byLeft.sublist(bestAt));
  }

  static List<OcrRow> _rowsOf(List<OcrLine> usable) {

    final sorted = [...usable]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <List<OcrLine>>[];

    for (final line in sorted) {
      List<OcrLine>? target;
      // Only the most recent rows can overlap because lines are sorted.
      for (var i = rows.length - 1; i >= 0 && i >= rows.length - 3; i--) {
        if (_overlaps(rows[i], line)) {
          target = rows[i];
          break;
        }
      }
      if (target == null) {
        rows.add([line]);
      } else {
        target.add(line);
      }
    }

    return [
      for (final row in rows)
        OcrRow([...row]..sort((a, b) => a.left.compareTo(b.left))),
    ];
  }

  static bool _overlaps(List<OcrLine> row, OcrLine line) {
    var top = row.first.top;
    var bottom = row.first.bottom;
    for (final s in row) {
      if (s.top < top) top = s.top;
      if (s.bottom > bottom) bottom = s.bottom;
    }
    final overlap =
        (line.bottom < bottom ? line.bottom : bottom) -
            (line.top > top ? line.top : top);
    final rowHeight = bottom - top;
    final shorter = line.height < rowHeight ? line.height : rowHeight;
    return shorter > 0 && overlap >= shorter * overlapThreshold;
  }
}

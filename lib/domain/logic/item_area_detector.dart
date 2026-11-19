import '../services/services.dart';
import 'item_line_parser.dart';
import 'ocr_row_assembler.dart';
import 'receipt_text_lines.dart';

/// The printed text found on a photo.
class TextBlock {
  const TextBlock(this.box, this.lineHeight);

  final ItemArea box;
  final double lineHeight;
}

/// A rectangle in image pixels.
class ItemArea {
  const ItemArea({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

/// Works out where the purchased items are on a receipt photo from the OCR
/// boxes, so the crop does not have to be drawn by hand. The area runs from
/// the first item to the last, plus the subtotal / tip / total lines under it.
class ItemAreaDetector {
  ItemAreaDetector._();

  /// The block of meaningful text on a non-meal receipt, padded.
  static ItemArea? textArea(List<OcrLine> lines) {
    final usable = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (usable.isEmpty || usable.any((l) => !l.hasGeometry)) return null;
    final rows = OcrRowAssembler.assemble(usable)
        .where((r) => ReceiptTextLines.isMeaningful(r.text))
        .toList();
    if (rows.isEmpty) return null;
    var left = rows.first.left;
    var top = rows.first.top;
    var right = rows.first.right;
    var bottom = rows.first.bottom;
    var heights = 0.0;
    for (final r in rows) {
      if (r.left < left) left = r.left;
      if (r.top < top) top = r.top;
      if (r.right > right) right = r.right;
      if (r.bottom > bottom) bottom = r.bottom;
      heights += r.height;
    }
    final pad = heights / rows.length;
    return ItemArea(
      left: left - pad,
      top: top - pad,
      right: right + pad,
      bottom: bottom + pad,
    );
  }

  /// Everything printed that OCR read: the box round it and the typical
  /// line height. Null when too little was read to trust.
  static TextBlock? textBlock(List<OcrLine> lines) {
    final usable = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (usable.length < 5 || usable.any((l) => !l.hasGeometry)) return null;
    var left = usable.first.left;
    var top = usable.first.top;
    var right = usable.first.right;
    var bottom = usable.first.bottom;
    final heights = <double>[];
    for (final l in usable) {
      if (l.left < left) left = l.left;
      if (l.top < top) top = l.top;
      if (l.right > right) right = l.right;
      if (l.bottom > bottom) bottom = l.bottom;
      heights.add(l.height);
    }
    heights.sort();
    return TextBlock(
      ItemArea(left: left, top: top, right: right, bottom: bottom),
      heights[heights.length ~/ 2],
    );
  }

  /// Text narrower than this share of the photo means the receipt sits in a
  /// wider scene (table, hands) that can be cut away. Wider text means the
  /// receipt fills the frame, and cutting could lose print OCR missed.
  static const double narrowText = 0.70;

  /// A cut has to remove at least this share of the photo to be worth it.
  static const double worthwhileCut = 0.15;

  /// Where to cut a [width] x [height] photo so it keeps the receipt and
  /// loses the table around it, for photos where the paper's edge could not
  /// be found (white paper on a pale table). Generous above and below, where
  /// logos, QR codes and faint headers sit that OCR may not have read. Null
  /// when the photo should be kept as it is.
  static ItemArea? receiptCrop(
    TextBlock text, {
    required int width,
    required int height,
  }) {
    final box = text.box;
    final textWidth = box.right - box.left;
    if (width <= 0 || height <= 0 || textWidth >= width * narrowText) {
      return null;
    }
    final padX = _larger(textWidth * 0.10, text.lineHeight * 2.5);
    final padY = _larger(height * 0.10, text.lineHeight * 3);
    final left = _clamp(box.left - padX, 0, width.toDouble());
    final right = _clamp(box.right + padX, 0, width.toDouble());
    final top = _clamp(box.top - padY, 0, height.toDouble());
    final bottom = _clamp(box.bottom + padY, 0, height.toDouble());
    if (right <= left || bottom <= top) return null;
    final kept = (right - left) * (bottom - top) / (width * height);
    if (kept > 1 - worthwhileCut) return null;
    return ItemArea(left: left, top: top, right: right, bottom: bottom);
  }

  static double _larger(double a, double b) => a > b ? a : b;
  static double _clamp(double v, double low, double high) =>
      v < low ? low : (v > high ? high : v);

  static ItemArea? detect(List<OcrLine> lines) {
    final usable = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (usable.isEmpty || usable.any((l) => !l.hasGeometry)) return null;

    final rows = OcrRowAssembler.assemble(usable);
    final items = ItemLineParser.extract([for (final r in rows) r.text]);
    if (items.isEmpty) return null;

    final first = items.first.firstRow;
    var end = items.last.lastRow;
    var extra = 0;
    for (var i = end + 1; i < rows.length && extra < 4; i++) {
      if (!ItemLineParser.isSummaryRow(rows[i].text)) break;
      end = i;
      extra++;
    }

    var left = rows[first].left;
    var top = rows[first].top;
    var right = rows[first].right;
    var bottom = rows[first].bottom;
    var heights = 0.0;
    for (var i = first; i <= end; i++) {
      final r = rows[i];
      if (r.left < left) left = r.left;
      if (r.top < top) top = r.top;
      if (r.right > right) right = r.right;
      if (r.bottom > bottom) bottom = r.bottom;
      heights += r.height;
    }
    final averageHeight = heights / (end - first + 1);
    final padY = averageHeight * 0.5;
    final padX = averageHeight * 1.0;
    return ItemArea(
      left: left - padX,
      top: top - padY,
      right: right + padX,
      bottom: bottom + padY,
    );
  }
}

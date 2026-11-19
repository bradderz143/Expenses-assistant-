import 'dart:typed_data';

import '../entities/receipt.dart';
import '../entities/translation_line.dart';
import '../entities/trip.dart';
import '../logic/item_area_detector.dart';

/// A line of text found by OCR with its bounding box in image pixels.
/// Kept free of `dart:ui` so parsing logic is testable in pure Dart.
class OcrLine {
  const OcrLine({
    required this.text,
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
  bool get hasGeometry => bottom > top;
}

class OcrResult {
  const OcrResult({required this.text, required this.lines});

  final String text;
  final List<OcrLine> lines;

  static const empty = OcrResult(text: '', lines: []);
}

abstract interface class OcrService {
  Future<OcrResult> recognise(String imagePath);

  Future<void> dispose();
}

abstract interface class TranslationService {
  /// Returns a BCP-47 code such as `es`, or null if undetermined.
  Future<String?> identifyLanguage(String text);

  bool supports(String languageCode);

  Future<bool> isModelDownloaded(String languageCode);

  Future<bool> downloadModel(String languageCode, {bool wifiOnly = false});

  Future<bool> deleteModel(String languageCode);

  /// Translates each text independently, preserving order.
  Future<List<String>> translateAll(
    List<String> texts, {
    required String from,
    String to = 'en',
  });

  Future<void> dispose();
}

/// Renders translated_items.pdf.
abstract interface class TranslationDocumentRenderer {
  Future<Uint8List> render({
    required Receipt receipt,
    required List<TranslationLine> lines,
    required DateTime generatedAt,
    Trip? trip,
    Uint8List? cropImage,
  });
}

/// Image work the translation flow needs. Implemented with the `image`
/// package; kept behind an interface so the domain stays pure Dart.
abstract interface class ImageProcessor {
  /// Straightens the photo, and trims the background around the paper when it
  /// can find the receipt edges confidently. Always writes [destPath].
  /// Returns whether the paper was found and the photo trimmed to it.
  Future<bool> cropToReceipt(String sourcePath, String destPath);

  /// Cuts the photo at [path] down to the receipt, judged by the [text] OCR
  /// read on it (see [ItemAreaDetector.receiptCrop]). Leaves the file
  /// untouched when the receipt already fills the frame or the cut would
  /// gain little. Returns whether it was cut.
  Future<bool> trimToText(String path, TextBlock text);

  /// Writes an upright copy of [sourcePath] (camera rotation applied, long
  /// side at most [maxSide] pixels) to [destPath]. OCR boxes measured on the
  /// copy line up with its pixels.
  Future<void> normalise(String sourcePath, String destPath, {int maxSide = 2400});

  /// Writes the given rectangle of [sourcePath] to [destPath]. Values outside
  /// the image are clamped.
  Future<void> crop(
    String sourcePath,
    String destPath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  });
}

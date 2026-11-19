import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/enums.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/entities/translation_line.dart';
import '../../domain/entities/trip.dart';
import '../../domain/logic/claim_documents.dart';
import '../../domain/logic/formatting.dart';
import '../../domain/reference/countries.dart';
import '../../domain/services/services.dart';

typedef FontLoader = Future<ByteData> Function(String assetPath);

/// Produces translated_items.pdf: the cropped item image alongside a table of
/// original wording and English translation, so an auditor can check one
/// against the other on a single page.
class PdfTranslationRenderer implements TranslationDocumentRenderer {
  PdfTranslationRenderer({required FontLoader fontLoader})
      : _fontLoader = fontLoader;

  final FontLoader _fontLoader;
  pw.Font? _regular;
  pw.Font? _bold;

  static const String regularFontAsset = 'assets/fonts/DejaVuSans.ttf';
  static const String boldFontAsset = 'assets/fonts/DejaVuSans-Bold.ttf';

  Future<void> _loadFonts() async {
    // DejaVu covers Latin, Greek and Cyrillic; the PDF built-in Helvetica
    // only covers Latin-1.
    _regular ??= pw.Font.ttf(await _fontLoader(regularFontAsset));
    _bold ??= pw.Font.ttf(await _fontLoader(boldFontAsset));
  }

  @override
  Future<Uint8List> render({
    required Receipt receipt,
    required List<TranslationLine> lines,
    required DateTime generatedAt,
    Trip? trip,
    Uint8List? cropImage,
  }) async {
    await _loadFonts();
    final regular = _regular!;
    final bold = _bold!;

    final doc = pw.Document(
      title: 'Translation - ${receipt.merchant ?? 'receipt'}',
      author: 'Expense Assistant',
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    final date = receipt.transactionDate;
    final wholeReceipt = lines.isNotEmpty &&
        lines.every((l) => l.category == ItemCategory.general);
    final language = Languages.nameOf(
      lines.isNotEmpty ? lines.first.sourceLanguage : receipt.detectedLanguage,
    );
    final headerStyle = pw.TextStyle(font: bold, fontSize: 9);
    const cellStyle = pw.TextStyle(fontSize: 9);

    pw.Widget cell(String text, {pw.TextStyle? style, bool alignRight = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: pw.Text(
          text,
          style: style ?? cellStyle,
          textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );
    }

    pw.Widget detail(String label, String value) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 90,
              child: pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 10)),
            ),
            pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
          ],
        ),
      );
    }

    // One small table per heading (Food, Drinks): original wording beside
    // the English. No quantities or prices: the receipt image shows those.
    pw.Widget groupTable(ItemCategory category, List<TranslationLine> group) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (!wholeReceipt) ...[
            pw.Text(category.label, style: pw.TextStyle(font: bold, fontSize: 11)),
            pw.SizedBox(height: 4),
          ],
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cell('Original ($language)', style: headerStyle),
                  cell('English', style: headerStyle),
                ],
              ),
              for (final line in group)
                pw.TableRow(
                  children: [
                    cell(line.originalText),
                    cell(line.translatedText),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 10),
        ],
      );
    }

    final tables = <pw.Widget>[
      for (final category in ItemCategory.values)
        if (lines.any((l) => l.category == category))
          groupTable(
            category,
            lines.where((l) => l.category == category).toList(),
          ),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated ${Formatting.displayDate(generatedAt)} by Expense Assistant',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(
              wholeReceipt ? 'Receipt translation' : 'Receipt item translation',
              style: pw.TextStyle(font: bold, fontSize: 16)),
          pw.SizedBox(height: 10),
          detail('Merchant', receipt.merchant ?? '(not recorded)'),
          detail('Date',
              date == null ? '(not recorded)' : Formatting.displayDate(date)),
          detail('Total', receipt.amount?.toString() ?? '(not recorded)'),
          detail('Location', receipt.country),
          if (trip != null) detail('Trip', trip.name),
          detail('Language', '$language to English'),
          pw.SizedBox(height: 12),
          if (cropImage != null) ...[
            pw.Text(
                wholeReceipt
                    ? 'Receipt text (cropped from original receipt)'
                    : 'Purchased items (cropped from original receipt)',
                style: pw.TextStyle(font: bold, fontSize: 10)),
            pw.SizedBox(height: 6),
            pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              ),
              child: pw.Image(
                pw.MemoryImage(cropImage),
                height: 300,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 14),
          ],
          pw.Text('Translation', style: pw.TextStyle(font: bold, fontSize: 10)),
          pw.SizedBox(height: 6),
          ...tables,
          pw.Text(
            ClaimDocuments.translationProvenance(lines),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
          ),
        ],
      ),
    );

    return doc.save();
  }
}

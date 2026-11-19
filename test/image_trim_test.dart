import 'dart:io';

import 'package:expense_assistant/data/services/receipt_image_processor.dart';
import 'package:expense_assistant/domain/logic/item_area_detector.dart';
import 'package:expense_assistant/domain/services/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  final processor = ReceiptImageProcessor();

  setUp(() async => temp = await Directory.systemTemp.createTemp('trim_test'));
  tearDown(() async => temp.delete(recursive: true));

  /// A photo of [paper] (left, top, right, bottom) lying on a [table].
  String photo(String name, {required int table, List<int>? paper}) {
    final image = img.Image(width: 600, height: 800);
    img.fill(image, color: img.ColorRgb8(table, table, table));
    if (paper != null) {
      img.fillRect(
        image,
        x1: paper[0],
        y1: paper[1],
        x2: paper[2],
        y2: paper[3],
        color: img.ColorRgb8(245, 245, 245),
      );
    }
    final path = p.join(temp.path, name);
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return path;
  }

  img.Image read(String path) => img.decodeImage(File(path).readAsBytesSync())!;

  test('white paper on a dark table is found and trimmed to', () async {
    final source = photo('dark.jpg', table: 40, paper: [150, 100, 450, 700]);
    final out = p.join(temp.path, 'out.jpg');
    expect(await processor.cropToReceipt(source, out), isTrue);
    final cut = read(out);
    expect(cut.width, inInclusiveRange(290, 340));
    expect(cut.height, inInclusiveRange(590, 650));
  });

  test('paper the same white as the table cannot be found: photo kept whole',
      () async {
    final source = photo('white.jpg', table: 245, paper: [150, 100, 450, 700]);
    final out = p.join(temp.path, 'out.jpg');
    expect(await processor.cropToReceipt(source, out), isFalse);
    expect(read(out).width, 600);
    expect(read(out).height, 800);
  });

  TextBlock text(double left, double top, double right, double bottom,
          {double lineHeight = 30}) =>
      TextBlock(
        ItemArea(left: left, top: top, right: right, bottom: bottom),
        lineHeight,
      );

  test('a receipt in a wide scene is cut out with generous margins', () {
    // 964 x 2015 like the the restaurant bill photo: text 197..774 wide.
    final area = ItemAreaDetector.receiptCrop(
      text(197, 342, 774, 1802, lineHeight: 20),
      width: 964,
      height: 2015,
    )!;
    expect(area.left, closeTo(197 - 57.7, 1)); // 10% of the text width
    expect(area.right, closeTo(774 + 57.7, 1));
    expect(area.top, closeTo(342 - 201.5, 1)); // 10% of the photo height
    expect(area.bottom, closeTo(1802 + 201.5, 1));
  });

  test('a close-up where the text fills the width is never cut', () {
    // Unread print (a QR code, a logo, a faded header) could be lost.
    expect(
      ItemAreaDetector.receiptCrop(
        text(170, 120, 1130, 2017),
        width: 1300,
        height: 2400,
      ),
      isNull,
    );
  });

  test('a cut that would gain little is skipped', () {
    expect(
      ItemAreaDetector.receiptCrop(
        text(120, 20, 520, 780),
        width: 600,
        height: 800,
      ),
      isNull,
    );
  });

  test('the cut stays inside the photo', () {
    final area = ItemAreaDetector.receiptCrop(
      text(100, 5, 300, 795),
      width: 600,
      height: 800,
    )!;
    expect(area.top, 0);
    expect(area.bottom, 800);
    expect(area.left, greaterThanOrEqualTo(0));
  });

  test('trimToText cuts the file, or leaves it byte for byte', () async {
    final wide = photo('wide.jpg', table: 238);
    expect(await processor.trimToText(wide, text(200, 300, 380, 500)), isTrue);
    expect(read(wide).width, lessThan(600));

    final close = photo('close.jpg', table: 238);
    final before = File(close).readAsBytesSync();
    expect(
      await processor.trimToText(close, text(40, 40, 560, 760)),
      isFalse,
    );
    expect(File(close).readAsBytesSync(), before);
  });

  test('the text block is everything read, with the typical line height', () {
    final lines = [
      for (var i = 0; i < 30; i++)
        OcrLine(
          text: 'row $i',
          left: 200,
          top: 300.0 + i * 40,
          right: 800,
          bottom: 330.0 + i * 40,
        ),
    ];
    final block = ItemAreaDetector.textBlock(lines)!;
    expect(block.box.left, 200);
    expect(block.box.right, 800);
    expect(block.box.top, 300);
    expect(block.box.bottom, 330.0 + 29 * 40);
    expect(block.lineHeight, 30);
    expect(ItemAreaDetector.textBlock(lines.take(4).toList()), isNull);
    expect(ItemAreaDetector.textBlock(const [OcrLine(text: 'no boxes')]),
        isNull);
  });
}

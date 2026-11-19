import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../../domain/logic/item_area_detector.dart';
import '../../domain/services/services.dart';

/// Decodes, rotates, resizes and crops receipt photos. The heavy work runs in
/// a background isolate so the screen stays responsive.
class ReceiptImageProcessor implements ImageProcessor {
  @override
  Future<void> normalise(
    String sourcePath,
    String destPath, {
    int maxSide = 2400,
  }) {
    return Isolate.run(() {
      final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (decoded == null) {
        throw const FormatException('Could not read the receipt image.');
      }
      var image = img.bakeOrientation(decoded);
      if (math.max(image.width, image.height) > maxSide) {
        image = image.width >= image.height
            ? img.copyResize(image, width: maxSide)
            : img.copyResize(image, height: maxSide);
      }
      File(destPath).writeAsBytesSync(img.encodeJpg(image, quality: 92));
    });
  }

  @override
  Future<bool> cropToReceipt(String sourcePath, String destPath) {
    return Isolate.run(() {
      final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (decoded == null) {
        throw const FormatException('Could not read the receipt image.');
      }
      var image = img.bakeOrientation(decoded);
      if (math.max(image.width, image.height) > 2400) {
        image = image.width >= image.height
            ? img.copyResize(image, width: 2400)
            : img.copyResize(image, height: 2400);
      }
      final bounds = _paperBounds(image);
      if (bounds != null) {
        image = img.copyCrop(
          image,
          x: bounds[0],
          y: bounds[1],
          width: bounds[2] - bounds[0],
          height: bounds[3] - bounds[1],
        );
      }
      File(destPath).writeAsBytesSync(img.encodeJpg(image, quality: 92));
      return bounds != null;
    });
  }

  @override
  Future<bool> trimToText(String path, TextBlock text) {
    return Isolate.run(() {
      final image = img.decodeImage(File(path).readAsBytesSync());
      if (image == null) return false;
      final area = ItemAreaDetector.receiptCrop(
        text,
        width: image.width,
        height: image.height,
      );
      if (area == null) return false;
      final x0 = area.left.floor().clamp(0, image.width - 1).toInt();
      final y0 = area.top.floor().clamp(0, image.height - 1).toInt();
      final x1 = area.right.ceil().clamp(x0 + 1, image.width).toInt();
      final y1 = area.bottom.ceil().clamp(y0 + 1, image.height).toInt();
      final cut = img.copyCrop(
        image,
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
      );
      File(path).writeAsBytesSync(img.encodeJpg(cut, quality: 92));
      return true;
    });
  }

  /// Finds the bright paper against a darker background. Returns
  /// [left, top, right, bottom] in image pixels, or null when the paper fills
  /// the frame or cannot be told apart from the background.
  static List<int>? _paperBounds(img.Image image) {
    final small = image.width >= image.height
        ? img.copyResize(image, width: 320)
        : img.copyResize(image, height: 320);
    final w = small.width;
    final h = small.height;
    final lum = List<int>.filled(w * h, 0);
    final hist = List<int>.filled(256, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final px = small.getPixel(x, y);
        final v = (0.299 * px.r + 0.587 * px.g + 0.114 * px.b).round().clamp(0, 255).toInt();
        lum[y * w + x] = v;
        hist[v]++;
      }
    }
    // Otsu threshold.
    final total = w * h;
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var sumB = 0.0;
    var wB = 0;
    var best = 0.0;
    var threshold = 128;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }
    if (best == 0) return null;

    final colBright = List<int>.filled(w, 0);
    final rowBright = List<int>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (lum[y * w + x] > threshold) {
          colBright[x]++;
          rowBright[y]++;
        }
      }
    }
    int first(List<int> counts, int length) {
      for (var i = 0; i < counts.length; i++) {
        if (counts[i] >= length * 0.25) return i;
      }
      return 0;
    }

    int last(List<int> counts, int length) {
      for (var i = counts.length - 1; i >= 0; i--) {
        if (counts[i] >= length * 0.25) return i;
      }
      return counts.length - 1;
    }

    final x0 = first(colBright, h);
    final x1 = last(colBright, h) + 1;
    final y0 = first(rowBright, w);
    final y1 = last(rowBright, w) + 1;
    if (x1 <= x0 || y1 <= y0) return null;
    final area = (x1 - x0) * (y1 - y0) / total;
    // Not a clear paper shape, or nothing worth trimming.
    if (area < 0.2 || area > 0.92) return null;

    final padX = (w * 0.015).ceil();
    final padY = (h * 0.015).ceil();
    final sx = image.width / w;
    final sy = image.height / h;
    final left = ((x0 - padX).clamp(0, w - 1) * sx).floor();
    final top = ((y0 - padY).clamp(0, h - 1) * sy).floor();
    final right = (((x1 + padX).clamp(1, w)) * sx).ceil().clamp(left + 1, image.width).toInt();
    final bottom = (((y1 + padY).clamp(1, h)) * sy).ceil().clamp(top + 1, image.height).toInt();
    return [left, top, right, bottom];
  }

  @override
  Future<void> crop(
    String sourcePath,
    String destPath, {
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    return Isolate.run(() {
      final image = img.decodeImage(File(sourcePath).readAsBytesSync());
      if (image == null) {
        throw const FormatException('Could not read the receipt image.');
      }
      int within(int value, int low, int high) =>
          value < low ? low : (value > high ? high : value);
      final x0 = within(left.floor(), 0, image.width - 1);
      final y0 = within(top.floor(), 0, image.height - 1);
      final x1 = within(right.ceil(), x0 + 1, image.width);
      final y1 = within(bottom.ceil(), y0 + 1, image.height);
      final cropped = img.copyCrop(
        image,
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
      );
      File(destPath).writeAsBytesSync(img.encodeJpg(cropped, quality: 92));
    });
  }
}

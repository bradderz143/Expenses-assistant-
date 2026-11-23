// ignore_for_file: avoid_print
import 'dart:io';
import 'package:expense_assistant/domain/logic/receipt_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('probe', () {
    print('clashes: ${ReceiptLabels.selfCheck()}');
    print('size: ${ReceiptLabels.size}');
    final lines = File('test/zz_lines.txt').readAsLinesSync();
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      print('${l.padRight(44)} -> ${ReceiptLabels.translate(l, 'es')}');
    }
  });
}
